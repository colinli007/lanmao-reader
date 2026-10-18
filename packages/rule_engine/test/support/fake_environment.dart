import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/host/cookie_store.dart';

/// 测试用的环境：按地址返回预设的响应，记录收到的请求；取消时抛出 [CancelledForTest]。
final class FakeEnvironment implements RuleEnvironment {
  FakeEnvironment([Map<String, Object> responses = const {}]) : _responses = {...responses};

  /// 地址 → 响应。值是 [String]（按 UTF-8 编码，状态码 200）或 [HttpResult]；
  /// 是 [List] 时依次返回其中的响应，最后一个一直重复。
  final Map<String, Object> _responses;
  final List<HttpRequest> requests = [];

  @override
  final Pointer<Int32> abortSignal = calloc<Int32>();

  /// 书源级状态和 Cookie，与主 isolate 上的 `RuleHost` 用同一套语义。
  final SourceStore sourceStore = MemorySourceStore();
  final CookieStore cookieStore = CookieStore();

  /// 收到的书源日志。
  final List<SourceLog> logs = [];

  @override
  Object? store(StoreRequest request) => runStoreRequest(request, sourceStore, cookieStore);

  @override
  void log(SourceLog log) => logs.add(log);

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
    var response = _responses[request.url];
    if (response is List<Object>) response = response.length > 1 ? response.removeAt(0) : response.single;
    return switch (response) {
      HttpResult() => response,
      String() => HttpResult(statusCode: 200, url: request.url, body: Uint8List.fromList(utf8.encode(response))),
      _ => HttpResult(statusCode: 404, url: request.url, body: Uint8List(0)),
    };
  }

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => [for (final request in requests) fetch(request)];
}

/// 测试用的书源：地址 `https://a.com`，名字 `A`，[extra] 覆盖或补充字段。
BookSource testSource([Map<String, Object?> extra = const {}]) =>
    loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': 'A', ...extra})).sources.single;

final class CancelledForTest implements Exception {
  const CancelledForTest();
}
