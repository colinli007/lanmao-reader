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

/// 主 isolate 上执行规则引擎的网络请求，交给 `WorkerPool` 作为宿主请求的处理方：
///
/// ```dart
/// final host = RuleHost();
/// final pool = WorkerPool(host.handle, size: 4);
/// ```
///
/// 持有全部 worker 共用的 Cookie 和限速记录。用 `dart:io` 的 `HttpClient`：手动跟随重定向（每一跳合并和保存 Cookie），
/// 接受无效证书，连接超时 15 秒，单次请求总超时 60 秒，非 2xx 响应照常返回。
final class RuleHost {
  RuleHost({this.connectionTimeout = const Duration(seconds: 15), this.callTimeout = const Duration(seconds: 60)});

  final Duration connectionTimeout;
  final Duration callTimeout;
  final CookieStore cookieStore = CookieStore();
  final RateLimiter rateLimiter = RateLimiter();

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
      default:
        throw UnsupportedError('未知的宿主请求：${call.op}');
    }
  }

  /// 执行一个请求：限速、附加书源域名的 Cookie、非 2xx 时按 `retry` 重试。[cancelled] 完成时中断请求。
  Future<HttpResult> execute(HttpRequest request, {Future<void>? cancelled}) async {
    await rateLimiter.acquire(request.sourceUrl, request.concurrentRate);
    final headers = {...request.headers};
    // 每个请求都带上书源域名的 Cookie，请求头里已有的值优先（MD3 的 AnalyzeUrl.setCookie）
    final stored = cookieStore.getCookie(cookieDomain(request.sourceUrl));
    if (stored.isNotEmpty) {
      final merged = mergeCookies([stored, headers['Cookie']]);
      if (merged != null) headers['Cookie'] = merged;
    }

    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..badCertificateCallback = ((cert, host, port) => true);
    unawaited(cancelled?.then((_) => client.close(force: true)));
    try {
      late HttpResult result;
      for (var attempt = 0; attempt <= request.retry; attempt++) {
        result = await _send(client, request, headers).timeout(callTimeout);
        if (result.statusCode >= 200 && result.statusCode < 300) break;
      }
      return result;
    } finally {
      client.close(force: true);
    }
  }

  static const int _maxFollowUps = 20;

  Future<HttpResult> _send(HttpClient client, HttpRequest request, Map<String, String> headers) async {
    var url = Uri.parse(request.url);
    var method = request.method;
    var body = request.body;
    final requestHeaders = {...headers};
    for (var followUps = 0; ; followUps++) {
      final hopHeaders = {...requestHeaders};
      if (request.enabledCookieJar) {
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
      if (request.enabledCookieJar) cookieStore.saveResponse(url, response.headers['set-cookie'] ?? const []);

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (_isRedirect(response.statusCode) && location != null) {
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
    response.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(', '));
    return HttpResult(
      statusCode: response.statusCode,
      url: url.toString(),
      headers: headers,
      body: body,
      redirected: redirected,
    );
  }
}
