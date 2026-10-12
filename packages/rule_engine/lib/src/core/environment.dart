import 'dart:ffi';
import 'dart:typed_data';

/// 规则引擎核心层对外部的全部依赖：网络和取消。
///
/// 核心层是同步代码，不感知 isolate。worker 端用阻塞桥实现（网络交给主 isolate），
/// 测试用回放录制样例的实现，不用起 isolate，也不连网。
abstract interface class RuleEnvironment {
  /// 同步执行一个请求。
  HttpResult fetch(HttpRequest request);

  /// 同步执行一批请求，由执行方并发，结果按提交顺序返回。
  List<HttpResult> fetchAll(List<HttpRequest> requests);

  /// 任务被取消或超时时抛出取消错误。
  void checkCancelled();

  /// 中止标志，交给书源正则的匹配，被设置后正在执行的匹配会停下。
  Pointer<Int32> get abortSignal;
}

/// worker 构造好的请求：地址、请求头、请求体都已经编码完成，执行方不需要理解书源。
final class HttpRequest {
  const HttpRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    required this.sourceUrl,
    this.enabledCookieJar = false,
    this.concurrentRate,
    this.retry = 0,
  });

  factory HttpRequest.fromJson(Map<String, Object?> json) => HttpRequest(
    url: json['url'] as String,
    method: json['method'] as String,
    headers: (json['headers'] as Map).cast<String, String>(),
    body: json['body'] as String?,
    sourceUrl: json['sourceUrl'] as String,
    enabledCookieJar: json['enabledCookieJar'] as bool,
    concurrentRate: json['concurrentRate'] as String?,
    retry: json['retry'] as int,
  );

  final String url;

  /// `GET`、`POST` 或 `HEAD`。
  final String method;
  final Map<String, String> headers;
  final String? body;

  /// 书源地址：Cookie 按它的注册域名附加，限速也按它分组。
  final String sourceUrl;
  final bool enabledCookieJar;
  final String? concurrentRate;

  /// 非 2xx 响应的重试次数。
  final int retry;

  Map<String, Object?> toJson() => {
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'sourceUrl': sourceUrl,
    'enabledCookieJar': enabledCookieJar,
    'concurrentRate': concurrentRate,
    'retry': retry,
  };

  @override
  String toString() => '$method $url';
}

/// 响应：原始字节、最终地址（重定向之后）和响应头，解码由核心层完成。
final class HttpResult {
  const HttpResult({
    required this.statusCode,
    required this.url,
    this.headers = const {},
    required this.body,
    this.redirected = false,
  });

  final int statusCode;

  /// 最终地址，后续的相对地址按它解析。
  final String url;

  /// 响应头，名字是小写，同名的多个值用逗号连接。
  final Map<String, String> headers;
  final Uint8List body;

  /// 发生过重定向（OkHttp 的 `priorResponse?.isRedirect`）。
  final bool redirected;
}
