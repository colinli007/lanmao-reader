import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rule_engine/rule_engine.dart';

/// 测试用的环境：按地址返回预设的响应，记录收到的请求；取消时抛出 [CancelledForTest]。
final class FakeEnvironment implements RuleEnvironment {
  FakeEnvironment([Map<String, Object> responses = const {}]) : _responses = {...responses};

  /// 地址 → 响应。值是 [String]（按 UTF-8 编码，状态码 200）或 [HttpResult]。
  final Map<String, Object> _responses;
  final List<HttpRequest> requests = [];

  @override
  final Pointer<Int32> abortSignal = calloc<Int32>();

  void respond(String url, Object response) => _responses[url] = response;

  void cancel() => abortSignal.value = 1;

  void dispose() => calloc.free(abortSignal);

  @override
  void checkCancelled() {
    if (abortSignal.value != 0) throw const CancelledForTest();
  }

  @override
  HttpResult fetch(HttpRequest request) {
    checkCancelled();
    requests.add(request);
    final response = _responses[request.url];
    return switch (response) {
      HttpResult() => response,
      String() => HttpResult(statusCode: 200, url: request.url, body: Uint8List.fromList(utf8.encode(response))),
      _ => HttpResult(statusCode: 404, url: request.url, body: Uint8List(0)),
    };
  }

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => [for (final request in requests) fetch(request)];
}

final class CancelledForTest implements Exception {
  const CancelledForTest();
}
