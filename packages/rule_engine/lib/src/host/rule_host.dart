import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';

import '../core/environment.dart';
import '../core/http_frame.dart';
import '../net/public_suffix.dart';
import '../worker/worker_environment.dart';
import 'cookie_store.dart';
import 'rate_limiter.dart';
import 'source_store.dart';

/// 主 isolate 上执行规则引擎的网络请求，交给 `WorkerPool` 作为宿主请求的处理方：
///
/// ```dart
/// final host = RuleHost();
/// final pool = WorkerPool(host.handle, size: 4);
/// ```
///
/// 持有全部 worker 共用的 Cookie、书源级状态（[SourceStore]）和限速记录。用 `dart:io` 的 `HttpClient`：
/// 手动跟随重定向（每一跳合并和保存 Cookie），接受无效证书，连接超时 15 秒，单次请求总超时 60 秒，非 2xx 响应照常返回。
///
/// 要落盘时传入自己的 [SourceStore] 和带初始值、变更回调的 [CookieStore]。
///
/// 书源 JS 的调试日志在写入时交给 [onLog]，没有设置时丢弃。
/// 响应头按 UTF-8 解码（source-request「响应处理」，fix-md3-diff-findings 设计 D1）：`dart:io` 把响应头的字节按 Latin-1
/// 解成字符，OkHttp 按 UTF-8。值里有 0x80 到 0xFF 的字符、且全部不超过 0xFF 时，按 Latin-1 还原成字节再按 UTF-8 解码；
/// 不是合法 UTF-8 时保留原样。
String utf8Header(String value) {
  if (!value.codeUnits.any((unit) => unit >= 0x80) || value.codeUnits.any((unit) => unit > 0xFF)) return value;
  try {
    return utf8.decode(latin1.encode(value));
  } on FormatException {
    return value;
  }
}

final class RuleHost {
  RuleHost({
    this.connectionTimeout = const Duration(seconds: 15),
    this.callTimeout = const Duration(seconds: 60),
    SourceStore? store,
    CookieStore? cookieStore,
    this.onLog,
  }) : store = store ?? MemorySourceStore(),
       cookieStore = cookieStore ?? CookieStore();

  final Duration connectionTimeout;
  final Duration callTimeout;
  final CookieStore cookieStore;
  final RateLimiter rateLimiter = RateLimiter();
  final SourceStore store;
  final void Function(SourceLog log)? onLog;

  /// `WorkerPool` 的宿主请求处理方。不认识的请求抛出 [UnsupportedError]。
  Future<Object?> handle(HostCall call) async {
    switch (call.op) {
      case RuleHostOps.http:
        final request = HttpRequest.fromJson((call.payload as Map).cast<String, Object?>());
        return encodeHttpResults([await execute(request, cancelled: call.cancelled)]);
      case RuleHostOps.httpBatch:
        final requests = [
          for (final json in call.payload as List) HttpRequest.fromJson((json as Map).cast<String, Object?>()),
        ];
        return encodeHttpResults(await Future.wait([for (final r in requests) execute(r, cancelled: call.cancelled)]));
      case RuleHostOps.store:
        return runStoreRequest(StoreRequest.fromJson((call.payload as Map).cast<String, Object?>()), store, cookieStore);
      case RuleHostOps.log:
        onLog?.call(SourceLog.fromJson((call.payload as Map).cast<String, Object?>()));
        return null;
      default:
        throw UnsupportedError('未知的宿主请求：${call.op}');
    }
  }

  /// 执行一个请求：限速、附加书源域名的 Cookie、非 2xx 时按 `retry` 重试。[cancelled] 完成时中断请求。
  /// 直连请求（[HttpRequest.direct]）不带 Cookie、不跟随重定向，状态码大于等于 400 时抛出 [HttpException]。
  Future<HttpResult> execute(HttpRequest request, {Future<void>? cancelled}) async {
    await rateLimiter.acquire(request.sourceUrl, request.concurrentRate);
    final headers = {...request.headers};
    // 每个请求都带上书源域名的 Cookie，请求头里已有的值优先（MD3 的 AnalyzeUrl.setCookie）
    final stored = request.direct ? '' : cookieStore.getCookie(cookieDomain(request.sourceUrl));
    if (stored.isNotEmpty) {
      final merged = mergeCookies([stored, headers['Cookie']]);
      if (merged != null) headers['Cookie'] = merged;
    }

    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..badCertificateCallback = ((cert, host, port) => true);
    unawaited(cancelled?.then((_) => client.close(force: true)));
    final timeout = request.timeout ?? (request.direct ? _directTimeout : callTimeout);
    try {
      late HttpResult result;
      for (var attempt = 0; attempt <= request.retry; attempt++) {
        result = await _send(client, request, headers).timeout(timeout);
        if (result.statusCode >= 200 && result.statusCode < 300) break;
      }
      if (request.direct && result.statusCode >= 400) {
        // Jsoup 的 HttpStatusException
        throw HttpException('HTTP error fetching URL. Status=${result.statusCode}, URL=[${result.url}]');
      }
      return result;
    } finally {
      client.close(force: true);
    }
  }

  /// Jsoup 的默认超时。
  static const Duration _directTimeout = Duration(seconds: 30);

  static const int _maxFollowUps = 20;

  Future<HttpResult> _send(HttpClient client, HttpRequest request, Map<String, String> headers) async {
    var url = Uri.parse(request.url);
    var method = request.method;
    var body = request.body;
    final requestHeaders = {...headers};
    for (var followUps = 0; ; followUps++) {
      final hopHeaders = {...requestHeaders};
      if (request.enabledCookieJar && !request.direct) {
        // 每一跳按实际请求的域名再合并一次，这次已保存的值优先（MD3 的 CookieManager.loadRequest）
        final merged = mergeCookies([hopHeaders['Cookie'], cookieStore.getCookie(cookieDomain(url.toString()))]);
        if (merged != null) hopHeaders['Cookie'] = merged;
      }
      final httpRequest = await client.openUrl(method, url);
      httpRequest.followRedirects = false;
      for (final MapEntry(:key, :value) in hopHeaders.entries) {
        httpRequest.headers.set(key, value, preserveHeaderCase: true);
      }
      if (body != null) {
        final bytes = utf8.encode(body);
        httpRequest.contentLength = bytes.length;
        httpRequest.add(bytes);
      }
      final response = await httpRequest.close();
      if (request.enabledCookieJar && !request.direct) {
        cookieStore.saveResponse(url, _setCookies(response));
      }

      final location = switch (response.headers.value(HttpHeaders.locationHeader)) {
        final value? => utf8Header(value),
        null => null,
      };
      if (_isRedirect(response.statusCode) && location != null && !request.direct) {
        await response.drain<void>();
        if (followUps >= _maxFollowUps) throw HttpException('重定向次数超过 $_maxFollowUps', uri: url);
        final next = url.resolve(location);
        if (next.scheme != 'http' && next.scheme != 'https') return _result(response, url, Uint8List(0), followUps > 0);
        // OkHttp：301、302、303 把非 GET/HEAD 改成不带请求体的 GET；307、308 保留方法和请求体
        if (method != 'GET' && method != 'HEAD' && response.statusCode != 307 && response.statusCode != 308) {
          method = 'GET';
          body = null;
          requestHeaders.removeWhere((name, _) => _bodyHeaders.contains(name.toLowerCase()));
        }
        if (next.host != url.host) requestHeaders.removeWhere((name, _) => name.toLowerCase() == 'authorization');
        url = next;
        continue;
      }
      final bytes = await response.fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
      return _result(response, url, bytes.takeBytes(), followUps > 0);
    }
  }

  static const Set<String> _bodyHeaders = {'content-type', 'content-length', 'transfer-encoding'};

  static bool _isRedirect(int status) => status == 300 || status == 301 || status == 302 || status == 303 || status == 307 || status == 308;

  static HttpResult _result(HttpClientResponse response, Uri url, Uint8List body, bool redirected) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) => headers[name.toLowerCase()] = values.map(utf8Header).join(', '));
    return HttpResult(
      statusCode: response.statusCode,
      url: url.toString(),
      headers: headers,
      body: body,
      redirected: redirected,
      setCookies: _setCookies(response),
    );
  }

  static List<String> _setCookies(HttpClientResponse response) => [...?response.headers['set-cookie']?.map(utf8Header)];
}
