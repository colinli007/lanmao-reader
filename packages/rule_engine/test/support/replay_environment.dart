import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rule_engine/rule_engine.dart';

/// 回放 `tool/smoke.dart --record` 录下的响应：按方法、地址、请求体匹配。没录到的请求直接失败，说明链路的行为变了。
final class ReplayEnvironment implements RuleEnvironment {
  ReplayEnvironment(List<Map<String, Object?>> records) {
    for (final record in records) {
      _responses[_key(record['method'] as String, record['url'] as String, record['body'] as String?)] = HttpResult(
        statusCode: record['status'] as int,
        url: record['finalUrl'] as String,
        headers: (record['headers'] as Map).cast<String, String>(),
        body: Uint8List.fromList(base64Decode(record['response'] as String)),
        redirected: record['redirected'] as bool,
      );
    }
  }

  final Map<String, HttpResult> _responses = {};

  @override
  final Pointer<Int32> abortSignal = calloc<Int32>();

  void dispose() => calloc.free(abortSignal);

  static String _key(String method, String url, String? body) => '$method $url ${body ?? ''}';

  @override
  void checkCancelled() {}

  @override
  HttpResult fetch(HttpRequest request) =>
      _responses[_key(request.method, request.url, request.body)] ?? (throw StateError('没有录制这个请求：$request'));

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => [for (final request in requests) fetch(request)];
}
