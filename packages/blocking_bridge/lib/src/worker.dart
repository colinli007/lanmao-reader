/// worker isolate 一侧：执行任务，任务里通过 [WorkerContext] 同步等待主 isolate。
library;

import 'dart:ffi';
import 'dart:isolate';

import 'package:native_synchronization/mailbox.dart';

import 'errors.dart';
import 'protocol.dart';

/// 内存不变量：Mailbox 必须由 isolate 级变量持有到 worker 退出。只放在局部变量里的话，
/// 任务执行中它可能被 GC，Finalizer 释放 native 内存后主侧再 put 就是 use-after-free。
/// worker 退出时 Dart 的 Finalizer 不运行，这块内存有意不释放，主侧迟到的 put 因此始终安全。
late final Mailbox _mailbox;
late final SendPort _toMain;
int _nextRequestId = 0;

/// worker isolate 入口。
void workerMain(SendPort toMain) {
  _toMain = toMain;
  _mailbox = Mailbox();
  final commands = ReceivePort()..listen((message) => _run(message as TaskMessage));
  toMain.send(WorkerReady(commands.sendPort, _mailbox.asSendable));
}

void _run(TaskMessage message) {
  final context = WorkerContext._(message.taskId, Pointer.fromAddress(message.abortAddress));
  WorkerContext._current = context;
  TaskDone done;
  try {
    done = TaskDone.value(message.taskId, message.body());
  } catch (error, stack) {
    done = TaskDone.error(message.taskId, error, '$stack');
  } finally {
    WorkerContext._current = null;
  }
  _report(done);
}

/// 返回值或异常对象不能跨 isolate 传递时，改成带原始信息的 [RemoteError]。
void _report(TaskDone done) {
  try {
    _toMain.send(done);
  } on ArgumentError catch (sendError) {
    final reason = done.failed ? '${done.error}' : '任务返回值不能跨 isolate 传递：$sendError';
    _toMain.send(TaskDone.error(done.taskId, RemoteError(reason, done.stack ?? ''), done.stack));
  }
}

/// 当前任务的上下文，只在 worker 执行任务期间可用。
///
/// worker 一次只执行一个任务，所以「当前任务」是确定的；在任务之前注册、跨任务复用的代码
/// （例如 JS 引擎的宿主函数）也应该通过 [current] 取上下文，而不是捕获某个任务的上下文。
final class WorkerContext {
  WorkerContext._(this._taskId, this.abortSignal);

  static WorkerContext? _current;

  static WorkerContext get current => _current ?? (throw StateError('当前不在 worker 任务中'));

  final int _taskId;

  /// 本任务的中止标志，非 0 表示任务已被取消或超时；交给 `JsEngine.eval(abortSignal:)`。
  /// Dart 代码不要直接读它，用 [isCancelled] / [throwIfCancelled]。
  final Pointer<Int32> abortSignal;

  /// 标志由主 isolate 在别的线程写入。VM 把 Pointer 读取当普通内存访问，内联进
  /// `while (!isCancelled) {}` 这样的循环后可能被外提到循环外、永远读不到新值；禁止内联，每次检查都真正读一次。
  @pragma('vm:never-inline')
  bool get isCancelled => abortSignal.value != 0;

  void throwIfCancelled() {
    if (isCancelled) throw const TaskCancelledException();
  }

  /// 同步等待主 isolate 处理宿主请求，返回宿主处理方的结果（JSON 值或 `Uint8List`）。
  ///
  /// 宿主处理失败抛出 [HostCallException]；任务已取消时抛出 [TaskCancelledException]，且不会把请求发给主 isolate。
  Object? callHost(String op, [Object? payload]) {
    throwIfCancelled();
    final requestId = _nextRequestId;
    _nextRequestId = (_nextRequestId + 1) & 0xffffffff;
    _toMain.send(HostRequest(_taskId, requestId, op, payload));

    final reply = Reply.decode(_mailbox.take());
    if (reply.requestId != requestId) {
      throw StateError('宿主回复错位：等待 $requestId，收到 ${reply.requestId}');
    }
    return switch (reply.kind) {
      ReplyKind.json || ReplyKind.bytes => reply.value,
      ReplyKind.error => throw HostCallException(reply.errorMessage),
      ReplyKind.cancelled => throw const TaskCancelledException(),
    };
  }
}
