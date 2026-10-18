import 'dart:ffi';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';

import '../core/environment.dart';
import '../core/http_frame.dart';

/// 宿主请求的名字，主 isolate 侧由 `RuleHost` 处理。
abstract final class RuleHostOps {
  static const String http = 'http';
  static const String httpBatch = 'httpBatch';
  static const String store = 'store';
  static const String log = 'log';
}

/// worker 里的 [RuleEnvironment]：网络、书源级状态和日志通过阻塞桥交给主 isolate，取消和中止信号来自当前任务。
///
/// 只能在 `WorkerPool` 的任务里使用。
final class WorkerRuleEnvironment implements RuleEnvironment {
  const WorkerRuleEnvironment();

  @override
  HttpResult fetch(HttpRequest request) =>
      decodeHttpResults(WorkerContext.current.callHost(RuleHostOps.http, request.toJson()) as Uint8List).single;

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) {
    if (requests.isEmpty) return [];
    final payload = [for (final request in requests) request.toJson()];
    return decodeHttpResults(WorkerContext.current.callHost(RuleHostOps.httpBatch, payload) as Uint8List);
  }

  @override
  Object? store(StoreRequest request) => WorkerContext.current.callHost(RuleHostOps.store, request.toJson());

  @override
  void log(SourceLog log) => WorkerContext.current.callHost(RuleHostOps.log, log.toJson());

  @override
  void checkCancelled() => WorkerContext.current.throwIfCancelled();

  @override
  Pointer<Int32> get abortSignal => WorkerContext.current.abortSignal;
}
