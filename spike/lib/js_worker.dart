/// 在后台 isolate 里运行 QuickJS，让书源 JS 能同步等待主 isolate 的异步结果。
///
/// Legado 书源里的 `var html = java.ajax(url)` 是同步语义。做法：
/// - 工作 isolate：JS 调用宿主函数 → 通过 SendPort 把请求发给主 isolate → `Mailbox.take()` 阻塞当前线程；
/// - 主 isolate：用普通的异步代码（HTTP、WebView、弹窗）处理请求 → `Mailbox.put()` 唤醒工作 isolate。
/// 主 isolate 永远不阻塞；每个工作 isolate 同一时刻只有一个未完成的请求，所以一个 Mailbox 就够。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';
import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

/// 主 isolate 上处理宿主请求的函数，[op] 是请求类型，如 `http.get`。
typedef HostHandler = Future<Object?> Function(String op, Object? payload);

/// 需要主 isolate 异步完成的宿主函数：JS 路径 → 请求类型。
const Map<String, String> _blockingFunctions = {
  'java.ajax': 'http.get',
  'java.getVerificationCode': 'ui.verificationCode',
};

class JsWorker {
  JsWorker._(this._isolate, this._commands, this._mailbox, this._subscription);

  final Isolate _isolate;
  final SendPort _commands;
  final Mailbox _mailbox;
  final StreamSubscription<Object?> _subscription;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextJobId = 0;
  bool _disposed = false;

  /// [requestTimeout]：主 isolate 处理单个宿主请求的上限，超时后一定会回复，保证工作 isolate 不会永久阻塞。
  static Future<JsWorker> spawn(
    HostHandler handler, {
    Duration requestTimeout = const Duration(seconds: 15),
  }) async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, fromWorker.sendPort, debugName: 'js-worker');

    final ready = Completer<_Ready>();
    late final JsWorker worker;
    final subscription = fromWorker.listen((message) {
      switch (message) {
        case _Ready():
          ready.complete(message);
        case _HostRequest(:final op, :final payload):
          unawaited(worker._answer(handler, op, payload, requestTimeout));
        case _JobResult(:final jobId, :final value, :final error):
          final completer = worker._pending.remove(jobId);
          if (error != null) {
            completer?.completeError(JsException(error));
          } else {
            completer?.complete(value);
          }
      }
    });

    final init = await ready.future;
    worker = JsWorker._(isolate, init.commands, init.mailbox.materialize(), subscription);
    return worker;
  }

  /// 在工作 isolate 里执行 [code]，[globals] 会先注入为全局变量。
  Future<Object?> run(String code, {Map<String, Object?> globals = const {}, Duration? timeout}) {
    if (_disposed) throw StateError('JsWorker 已释放');
    final jobId = _nextJobId++;
    final completer = Completer<Object?>();
    _pending[jobId] = completer;
    _commands.send(_Job(jobId, code, jsonEncode(globals), timeout?.inMilliseconds ?? 0));
    return completer.future;
  }

  /// 关闭 Mailbox 会唤醒正在阻塞的工作 isolate（take 抛出 StateError），然后再结束 isolate。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mailbox.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _subscription.cancel();
    for (final completer in _pending.values) {
      completer.completeError(StateError('JsWorker 已释放'));
    }
    _pending.clear();
  }

  Future<void> _answer(HostHandler handler, String op, Object? payload, Duration timeout) async {
    Map<String, Object?> reply;
    try {
      final value = await handler(op, payload).timeout(timeout);
      reply = {'ok': true, 'value': value};
    } on TimeoutException {
      reply = {'ok': false, 'error': '宿主请求超时（$op，${timeout.inMilliseconds}ms）'};
    } catch (e) {
      reply = {'ok': false, 'error': e.toString()};
    }
    if (_disposed) return;
    _mailbox.put(Uint8List.fromList(utf8.encode(jsonEncode(reply))));
  }
}

// ---------------------------------------------------------------- 工作 isolate

void _workerMain(SendPort toMain) {
  final mailbox = Mailbox();
  final commands = ReceivePort();
  final engine = JsEngine();

  Object? callMain(String op, Object? payload) {
    toMain.send(_HostRequest(op, payload));
    final reply = jsonDecode(utf8.decode(mailbox.take())) as Map<String, Object?>;
    if (reply['ok'] == true) return reply['value'];
    throw JsException(reply['error'] as String);
  }

  for (final MapEntry(key: path, value: op) in _blockingFunctions.entries) {
    engine.register(path, (args) => callMain(op, args));
  }
  // 纯计算的宿主函数直接在工作 isolate 里同步完成，不经过主 isolate
  engine.register('java.getString', (args) {
    final rule = args[0] as String;
    const jsPrefix = '@js:';
    if (!rule.startsWith(jsPrefix)) return rule;
    return engine.eval(rule.substring(jsPrefix.length));
  });

  commands.listen((message) {
    final job = message as _Job;
    try {
      final globals = jsonDecode(job.globalsJson) as Map<String, Object?>;
      globals.forEach(engine.setGlobal);
      final timeout = job.timeoutMs > 0 ? Duration(milliseconds: job.timeoutMs) : null;
      final value = engine.eval(job.code, timeout: timeout);
      toMain.send(_JobResult(job.jobId, value, null));
    } catch (e) {
      toMain.send(_JobResult(job.jobId, null, e is JsException ? e.message : e.toString()));
    }
  });

  toMain.send(_Ready(commands.sendPort, mailbox.asSendable));
}

// ---------------------------------------------------------------- 消息

final class _Ready {
  _Ready(this.commands, this.mailbox);
  final SendPort commands;
  final Sendable<Mailbox> mailbox;
}

final class _Job {
  _Job(this.jobId, this.code, this.globalsJson, this.timeoutMs);
  final int jobId;
  final String code;
  final String globalsJson;
  final int timeoutMs;
}

final class _HostRequest {
  _HostRequest(this.op, this.payload);
  final String op;
  final Object? payload;
}

final class _JobResult {
  _JobResult(this.jobId, this.value, this.error);
  final int jobId;
  final Object? value;
  final String? error;
}
