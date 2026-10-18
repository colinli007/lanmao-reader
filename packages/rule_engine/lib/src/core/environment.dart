import 'dart:ffi';
import 'dart:typed_data';

import 'source_state.dart';

export 'source_state.dart';

/// 规则引擎核心层对外部的全部依赖：网络、书源级状态、日志和取消。
///
/// 核心层是同步代码，不感知 isolate。worker 端用阻塞桥实现（交给主 isolate），
/// 测试用回放录制样例的实现，不用起 isolate，也不连网。
abstract interface class RuleEnvironment {
  /// 同步执行一个请求。
  HttpResult fetch(HttpRequest request);

  /// 同步执行一批请求，由执行方并发，结果按提交顺序返回。
  List<HttpResult> fetchAll(List<HttpRequest> requests);

  /// 读写一项书源级状态（缓存、书源变量、登录头、登录信息、Cookie），所有任务共用同一份。
  Object? store(StoreRequest request);

  /// 写一条书源调试日志，写入时就交给日志接收方。
  void log(SourceLog log);

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
    this.direct = false,
    this.timeout,
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
    direct: json['direct'] as bool,
    timeout: switch (json['timeoutMs']) {
      final int ms => Duration(milliseconds: ms),
      _ => null,
    },
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

  /// 直连（JS 的 `java.get`、`java.post`、`java.head`，MD3 用 Jsoup 发出）：不带书源域名的 Cookie、不保存响应的 Cookie、
  /// 不跟随重定向，没有 [timeout] 时 30 秒超时；状态码大于等于 400 时以错误结束。
  final bool direct;

  /// 这一个请求的总超时，为 null 时用执行方的默认值。
  final Duration? timeout;

  Map<String, Object?> toJson() => {
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'sourceUrl': sourceUrl,
    'enabledCookieJar': enabledCookieJar,
    'concurrentRate': concurrentRate,
    'retry': retry,
    'direct': direct,
    'timeoutMs': timeout?.inMilliseconds,
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
    this.setCookies = const [],
  });

  final int statusCode;

  /// 最终地址，后续的相对地址按它解析。
  final String url;

  /// 响应头，名字是小写，同名的多个值用逗号连接。
  final Map<String, String> headers;
  final Uint8List body;

  /// 发生过重定向（OkHttp 的 `priorResponse?.isRedirect`）。
  final bool redirected;

  /// 最后一个响应的 `Set-Cookie` 原文，逐条保留（[headers] 里用逗号连接后，含逗号的日期就分不开了）。
  final List<String> setCookies;
}
