/// 主 isolate 一侧：任务队列、派发、宿主请求、取消与截止时间、worker 状态机。
///
/// 全部状态只在主 isolate 上读写，事件按到达顺序处理、先到先得。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:native_synchronization/mailbox.dart';

import 'errors.dart';
import 'protocol.dart';
import 'worker.dart';

/// 主 isolate 上处理宿主请求的函数：普通的异步代码（HTTP、WebView、弹窗）。
/// 返回 JSON 能表示的值，或 `Uint8List`（按原始字节传给任务）。
typedef HostHandler = Future<Object?> Function(HostCall call);

/// 一次宿主请求。
final class HostCall {
  HostCall._(this._task, this._requestId, this.op, this.payload);

  final _Task<Object?> _task;
  final int _requestId;
  final String op;
  final Object? payload;
  final Completer<void> _ended = Completer<void>();
  bool _replied = false;
  bool _interactive = false;

  /// 所属任务在本请求回复之前就结束了（取消、超时、worker 退出、池关闭）时完成。
  /// 处理方据此中断网络请求、关闭弹窗；之后交回的结果会被丢弃。
  Future<void> get cancelled => _ended.future;

  /// 声明本请求在等待用户（验证码、手动过验证）：从现在到回复，所属任务的截止时间暂停计时。
  void markInteractive() {
    if (_interactive || _replied) return;
    _interactive = true;
    _task.pauseDeadline();
  }
}

/// 取消令牌，可以同时关联多个任务（例如一次搜索下所有书源的任务）。
final class CancelToken {
  final Set<_Task<Object?>> _tasks = {};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final task in _tasks.toList()) {
      task.pool._end(task, _EndReason.cancelled);
    }
  }
}

enum _EndReason { cancelled, timeout }

enum _WorkerState {
  /// 已 spawn，还没收到就绪消息。
  starting,
  idle,
  busy,

  /// 任务已取消或超时，等 worker 回报结束；超过宽限期就放弃。
  draining,

  /// 已放弃：不再接收任务、不计入容量，当前计算返回后退出，等 onExit 做清理。
  abandoned,
}

final class WorkerPool {
  /// [size]：最多同时执行的任务数，也是可用 worker 数的上限。
  /// [defaultTimeout]：任务的默认截止时间，从任务开始执行时计时。
  /// [cancelGracePeriod]：任务取消或超时后，worker 停下来的宽限期，超过就放弃它并补位。
  WorkerPool(
    this._hostHandler, {
    this.size = 4,
    this.defaultTimeout = const Duration(seconds: 60),
    this.cancelGracePeriod = const Duration(seconds: 2),
  }) : assert(size > 0);

  final HostHandler _hostHandler;
  final int size;
  final Duration defaultTimeout;
  final Duration cancelGracePeriod;

  final Queue<_Task<Object?>> _queue = Queue();
  final List<_Worker> _workers = [];

  /// 已放弃、还没退出的 worker：退出时释放中止标志、关闭端口。
  final Set<_Worker> _abandoned = {};
  int _nextTaskId = 0;
  bool _closed = false;

  static const _closedError = 'WorkerPool 已关闭';

  /// 可用的 worker 数（含正在启动的，不含已放弃的）。
  int get availableWorkers => _workers.length;

  /// 在 worker 里同步执行 [task]。[task] 捕获的变量和返回值必须能跨 isolate 传递。
  /// 截止时间从任务开始执行时计时，默认 [defaultTimeout]。
  Future<R> run<R>(R Function() task, {Duration? timeout, CancelToken? cancelToken}) {
    if (_closed) return Future.error(StateError(_closedError));
    if (cancelToken?.isCancelled ?? false) return Future.error(const TaskCancelledException());

    final entry = _Task<R>(this, _nextTaskId++, task, timeout ?? defaultTimeout, cancelToken);
    cancelToken?._tasks.add(entry);
    _queue.add(entry);
    _pump();
    return entry.future;
  }

  /// 关闭池：所有任务以错误结束，执行中的任务（包括阻塞中的）被中止，worker 在当前任务返回后退出。
  /// 之后提交立即失败。
  void close() {
    if (_closed) return;
    _closed = true;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().fail(StateError(_closedError));
    }
    for (final worker in [..._workers]) {
      final task = worker.task;
      if (task != null) {
        task.fail(StateError(_closedError));
        // 先写标志再 close Mailbox：阻塞中的 worker 醒来后，JS 被中止、不会在 catch 之后继续
        task.abort();
      }
      _abandon(worker);
    }
  }

  // ---------------------------------------------------------------- 派发

  void _pump() {
    if (_closed) return;
    while (_queue.isNotEmpty) {
      final idle = _firstIdle();
      if (idle == null) break;
      _start(idle, _queue.removeFirst());
    }
    // 补位只有这一条路径：可用数未到上限，且排队任务多于正在启动的 worker
    var starting = _workers.where((w) => w.state == _WorkerState.starting).length;
    while (_queue.length > starting && _workers.length < size) {
      _spawn();
      starting++;
    }
  }

  _Worker? _firstIdle() {
    for (final worker in _workers) {
      if (worker.state == _WorkerState.idle) return worker;
    }
    return null;
  }

  /// 任务闭包不能跨 isolate 传递时直接失败，worker 保持空闲。
  void _start(_Worker worker, _Task<Object?> task) {
    final abortCell = calloc<Int32>();
    try {
      worker.commands.send(TaskMessage(task.id, task.body, abortCell.address));
    } on ArgumentError catch (error, stack) {
      calloc.free(abortCell);
      task.fail(error, stack);
      return;
    }
    task
      ..abortCell = abortCell
      ..worker = worker
      ..startDeadline();
    worker
      ..task = task
      ..state = _WorkerState.busy;
  }

  void _spawn() {
    final worker = _Worker(RawReceivePort());
    worker.port.handler = (Object? message) => _onWorkerMessage(worker, message);
    _workers.add(worker);
    Isolate.spawn(
      workerMain,
      worker.port.sendPort,
      onExit: worker.port.sendPort,
      onError: worker.port.sendPort,
      debugName: 'blocking-bridge-worker',
    ).then((isolate) {
      worker.isolate = isolate;
      if (worker.state == _WorkerState.abandoned) isolate.kill(priority: Isolate.beforeNextEvent);
    }, onError: (Object error, StackTrace stack) {
      // isolate 都创建不出来（内存不足等），立刻重试也会失败：让排队的任务带着原因结束
      _forget(worker);
      while (_queue.isNotEmpty) {
        _queue.removeFirst().fail(error, stack);
      }
    });
  }

  // ---------------------------------------------------------------- worker 事件

  void _onWorkerMessage(_Worker worker, Object? message) {
    switch (message) {
      case WorkerReady(:final commands, :final mailbox):
        worker
          ..commands = commands
          ..mailbox = mailbox.materialize();
        if (worker.state == _WorkerState.starting) {
          worker.state = _WorkerState.idle;
          _pump();
        }
      case HostRequest():
        _onHostRequest(worker, message);
      case TaskDone():
        _onTaskDone(worker, message);
      case [final error, final stack]:
        // 未捕获的错误：isolate 随后会退出，onExit 时带上原因
        worker.lastError = '$error\n$stack';
      case null:
        _onExit(worker);
    }
  }

  void _onTaskDone(_Worker worker, TaskDone done) {
    final task = worker.task;
    if (task == null || task.id != done.taskId) return;
    task.releaseAbortCell();
    worker
      ..task = null
      ..cancelGraceTimer();
    if (worker.state == _WorkerState.abandoned) return;

    if (worker.state == _WorkerState.busy) {
      if (done.failed) {
        task.fail(done.error!, StackTrace.fromString(done.stack ?? ''));
      } else {
        task.complete(done.value);
      }
    }
    // 取消后的回报（draining）直接丢弃
    worker.state = _WorkerState.idle;
    _pump();
  }

  void _onExit(_Worker worker) {
    final task = worker.task;
    if (task != null) {
      // worker 已经不在了，不会再读中止标志
      task.releaseAbortCell();
      task.fail(WorkerExitedException(worker.lastError));
    }
    _forget(worker);
    _pump();
  }

  /// 不再接收任务、移出容量，然后补位。
  void _abandon(_Worker worker) {
    worker.abandon();
    _workers.remove(worker);
    _abandoned.add(worker);
    _pump();
  }

  void _forget(_Worker worker) {
    worker
      ..task = null
      ..cancelGraceTimer()
      ..mailboxOpen = false
      ..state = _WorkerState.abandoned;
    worker.port.close();
    _workers.remove(worker);
    _abandoned.remove(worker);
  }

  // ---------------------------------------------------------------- 宿主请求

  void _onHostRequest(_Worker worker, HostRequest request) {
    final task = worker.task;
    if (task == null || task.id != request.taskId || task.isEnded) {
      // 请求晚于取消到达：立即回复，不交给处理方，否则 worker 会卡到宽限期
      worker.wake(encodeCancelled(request.requestId));
      return;
    }
    final call = HostCall._(task, request.requestId, request.op, request.payload);
    task.inflight = call;
    unawaited(_handle(call));
  }

  Future<void> _handle(HostCall call) async {
    Uint8List reply;
    try {
      reply = encodeValue(call._requestId, await _hostHandler(call));
    } catch (error) {
      reply = encodeError(call._requestId, '$error');
    }
    _reply(call, reply);
  }

  /// 每个请求恰好回复一次：宿主处理完成和任务结束，谁先到用谁。
  void _reply(HostCall call, Uint8List reply) {
    if (call._replied) return;
    call._replied = true;
    final task = call._task;
    task.inflight = null;
    if (call._interactive) task.resumeDeadline();
    task.worker?.wake(reply);
  }

  // ---------------------------------------------------------------- 取消与截止时间

  void _end(_Task<Object?> task, _EndReason reason) {
    if (task.isEnded) return;
    task.fail(switch (reason) {
      _EndReason.cancelled => const TaskCancelledException(),
      _EndReason.timeout => TaskTimeoutException(task.timeout),
    });
    if (_queue.remove(task)) return;

    final worker = task.worker!;
    // 先写标志再唤醒：Mailbox 的互斥锁保证 worker 醒来后读得到标志
    task.abort();
    final call = task.inflight;
    if (call != null) _reply(call, encodeCancelled(call._requestId));
    if (worker.state == _WorkerState.busy) {
      worker
        ..state = _WorkerState.draining
        ..graceTimer = Timer(cancelGracePeriod, () {
          if (worker.state == _WorkerState.draining) _abandon(worker);
        });
    }
  }
}

final class _Task<R> {
  _Task(this.pool, this.id, this.body, this.timeout, this.cancelToken);

  final WorkerPool pool;
  final int id;
  final R Function() body;
  final Duration timeout;
  final CancelToken? cancelToken;
  final Completer<R> _completer = Completer<R>();

  /// 派发时分配；worker 回报结束或退出后才释放（之前 worker 可能还在读），释放后置空。
  Pointer<Int32>? abortCell;
  _Worker? worker;
  HostCall? inflight;

  Duration _remaining = Duration.zero;
  final Stopwatch _clock = Stopwatch();
  Timer? _deadline;

  Future<R> get future => _completer.future;

  /// 对提交方而言已经结束（worker 可能还没停下）。
  bool get isEnded => _completer.isCompleted;

  void complete(Object? value) {
    if (isEnded) return;
    _completer.complete(value as R);
    _finish();
  }

  void fail(Object error, [StackTrace? stack]) {
    if (isEnded) return;
    _completer.completeError(error, stack);
    _finish();
  }

  void _finish() {
    _deadline?.cancel();
    cancelToken?._tasks.remove(this);
    final call = inflight;
    if (call != null && !call._replied) call._ended.complete();
  }

  /// 设置中止标志：worker 里的 JS 被中止，`callHost` / `throwIfCancelled` 抛出取消。
  void abort() => abortCell?.value = 1;

  void releaseAbortCell() {
    final cell = abortCell;
    if (cell == null) return;
    abortCell = null;
    calloc.free(cell);
  }

  void startDeadline() {
    _remaining = timeout;
    resumeDeadline();
  }

  void pauseDeadline() {
    final deadline = _deadline;
    if (deadline == null) return;
    deadline.cancel();
    _deadline = null;
    _remaining -= _clock.elapsed;
    _clock.stop();
  }

  void resumeDeadline() {
    if (isEnded || _deadline != null) return;
    _clock
      ..reset()
      ..start();
    _deadline = Timer(_remaining, () => pool._end(this, _EndReason.timeout));
  }
}

final class _Worker {
  _Worker(this.port);

  final RawReceivePort port;
  Isolate? isolate;
  late SendPort commands;
  late Mailbox mailbox;
  bool mailboxOpen = true;
  _WorkerState state = _WorkerState.starting;
  _Task<Object?>? task;
  Timer? graceTimer;
  String? lastError;

  /// 回复阻塞在宿主请求上的 worker。Mailbox 关闭后（放弃后、退出后）不再写入。
  void wake(Uint8List reply) {
    if (!mailboxOpen) return;
    mailbox.put(reply);
  }

  void cancelGraceTimer() {
    graceTimer?.cancel();
    graceTimer = null;
  }

  /// 先 close Mailbox 唤醒阻塞中的 worker，再请求它在当前事件处理完后退出。
  ///
  /// 不用 `Isolate.immediate`：worker 的栈上可能有 native 帧（JS 调用的 Dart 宿主函数），
  /// 立即 kill 拆不过这些帧，整个进程会崩溃。
  void abandon() {
    cancelGraceTimer();
    if (mailboxOpen && state != _WorkerState.starting) mailbox.close();
    mailboxOpen = false;
    state = _WorkerState.abandoned;
    isolate?.kill(priority: Isolate.beforeNextEvent);
  }
}
