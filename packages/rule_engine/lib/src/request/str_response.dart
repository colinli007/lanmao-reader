import '../js/js_values.dart';

/// 解码之后的响应：链路用它的地址和正文，交给书源 JS 时是响应对象（MD3 的 `StrResponse`，
/// `java.get/post/head` 返回的 Jsoup `Connection.Response` 也用它表示）。
final class StrResponse implements JsHandle {
  StrResponse({
    required this.url,
    required this.body,
    this.statusCode = 200,
    this.headers = const {},
    this.setCookies = const [],
    this.redirected = false,
    String? message,
  }) : message = message ?? _reasonPhrase(statusCode);

  /// MD3 `StrResponse(url, body)`：新建 200/OK、空响应头；无效请求地址回退 localhost。
  factory StrResponse.fromUrl(String url, String? body) =>
      StrResponse(url: _requestUrl(url), body: body);

  static String _requestUrl(String value) {
    // Request.Builder.url 同时接受 ws/wss，先转换为 HTTP(S)。
    var text = value.trim();
    if (text.toLowerCase().startsWith('ws:')) {
      text = 'http:${text.substring(3)}';
    }
    if (text.toLowerCase().startsWith('wss:')) {
      text = 'https:${text.substring(4)}';
    }
    try {
      final uri = Uri.parse(text).normalizePath();
      if ((uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.port < 1 ||
          uri.port > 65535) {
        return 'http://localhost/';
      }
      return (uri.path.isEmpty ? uri.replace(path: '/') : uri).toString();
    } on FormatException {
      return 'http://localhost/';
    }
  }

  /// 请求出错时伪造的响应（MD3 `connect` 的行为）：状态码 200，正文是错误描述。
  StrResponse.error(this.url, String description)
    : body = description,
      statusCode = 200,
      headers = const {},
      setCookies = const [],
      redirected = false,
      message = 'OK';

  /// 最终地址（重定向之后）；选项 `type` 不为 null 时是请求地址。
  final String url;
  final String? body;
  final int statusCode;

  /// 响应头，名字是小写。
  final Map<String, String> headers;
  final List<String> setCookies;
  final bool redirected;
  final String message;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// 响应头，名字不区分大小写。
  String? header(String name) => headers[name.toLowerCase()];

  /// `Set-Cookie` 的名值对，同名时后面的覆盖前面的。
  Map<String, String> get cookies {
    final map = <String, String>{};
    for (final line in setCookies) {
      final pair = line.split(';').first;
      final eq = pair.indexOf('=');
      if (eq > 0) map[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
    return map;
  }

  @override
  String get jsType => 'res';

  StrResponse withBody(String? body) => StrResponse(
    url: url,
    body: body,
    statusCode: statusCode,
    headers: headers,
    setCookies: setCookies,
    redirected: redirected,
    message: message,
  );

  static String _reasonPhrase(int status) => switch (status) {
    200 => 'OK',
    201 => 'Created',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    500 => 'Internal Server Error',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    _ => '',
  };
}
