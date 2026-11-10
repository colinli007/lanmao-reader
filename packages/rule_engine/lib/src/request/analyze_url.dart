import 'dart:convert';
import 'dart:typed_data';

import '../chain/models.dart';
import '../core/environment.dart';
import '../core/errors.dart';
import '../core/source_task.dart';
import '../js/codec.dart';
import '../js/source_js.dart';
import '../json/json_text.dart';
import '../net/java_url.dart';
import '../rule/rule_data.dart';
import '../rule/rule_splitter.dart';
import '../text/charsets.dart';
import '../text/gson_json.dart';
import '../text/lenient_json.dart';
import 'response_decoder.dart';
import 'str_response.dart';

/// 书源没有 User-Agent 时补的默认值（MD3 用桌面 Chrome 的 UA）。
const String defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 照 MD3 的 `AnalyzeUrl` 构造请求，网络在主 isolate 上执行，Cookie 和限速也在那边：
/// 1. 依次执行地址里的 `@js:`、`<js>`（`result` 是到这一段为止的地址，普通文本里的 `@result` 换成上一段的结果）；
/// 2. `{{…}}` 一律按 JS 求值（读注入的 `key`、`page`、`baseUrl` 等），处理 `<a,b,c>` 页码列表；
/// 3. 切出 `,{选项}`，地址按基准地址转成绝对地址，选项里的 `js` 可以改地址和请求头；
/// 4. 按选项和请求头构造请求，编码查询串或表单。
///
/// URL 里的 JS 拿到的 `java` 就是这个对象：`put`、`get` 读写章节或本次链路的变量，`headerMap` 是请求头，
/// `getStrResponse` 重新发出这次请求。
final class SourceRequest {
  SourceRequest(
    this.task,
    this.mUrl, {
    this.key,
    this.page,
    String? baseUrl,
    this.ruleData,
    this.chapter,
    Map<String, String>? headers,
    this.timeout,
  }) {
    var base = baseUrl ?? '';
    final optionMatch = _paramPattern.firstMatch(base);
    if (optionMatch != null) base = base.substring(0, optionMatch.start);
    this.baseUrl = base;
    this.headers = headers != null ? {...headers} : sourceHeaders(task);
    this.headers.remove('proxy');
    initUrl();
  }

  final SourceTask task;

  /// 原始的地址规则。
  final String mUrl;
  final String? key;
  final int? page;

  /// `put` 的存储：书籍或本次链路的临时数据。
  final RuleData? ruleData;
  final ChapterData? chapter;

  /// 这一个请求的超时（`java.ajax`、`java.connect` 的参数）。
  final Duration? timeout;

  /// JS 里的 `baseUrl`：构造地址之前是传入的基准地址，之后是地址的协议加主机部分。
  late String baseUrl;

  /// 请求头，选项 `js` 里可以通过 `java.headerMap` 修改。
  late final Map<String, String> headers;

  /// 替换模板之后的地址（含 `,{选项}`）。
  late String ruleUrl;

  /// 绝对地址，不含选项。链路把它当作请求的地址（`baseUrl`）。
  late String url;

  /// 选项里的 `type`：不为 null 时结果是响应字节的十六进制字符串。
  String? type;

  /// 选项里的 `bodyJs`：拿到响应正文之后执行。
  String? bodyJs;

  // 构造地址时就编码好的请求：方法、地址、请求体、要覆盖的 Content-Type、重试次数
  String _method = 'GET';
  late String _requestUrl;
  String? _requestBody;
  String? _contentType;
  int _retry = 0;

  /// URL 里的 JS 读到的 `book`：只有详情、目录、正文阶段的书籍（MD3 的 `ruleData as? Book`）。
  Book? get book => ruleData is Book ? ruleData as Book : null;

  /// 重新构造地址（`java.initUrl()`）。
  void initUrl() {
    ruleUrl = mUrl;
    _analyzeJs();
    _replaceKeyPageJs();
    _analyzeUrl();
  }

  /// 依次执行 `@js:`、`<js>` 段，`result` 是到这一段为止的地址；返回值转成文本（null 是 `null`）。
  void _analyzeJs() {
    var start = 0;
    var result = ruleUrl;
    for (final match in _jsPattern.allMatches(ruleUrl)) {
      if (match.start > start) {
        final text = _trimJava(ruleUrl.substring(start, match.start));
        if (text.isNotEmpty) result = text.replaceAll('@result', result);
      }
      final code = (match.group(2) ?? '').isEmpty ? match.group(1) ?? '' : match.group(2)!;
      result = _text(_eval(code, result: result));
      start = match.end;
    }
    if (ruleUrl.length > start) {
      final text = _trimJava(ruleUrl.substring(start));
      if (text.isNotEmpty) result = text.replaceAll('@result', result);
    }
    ruleUrl = result;
  }

  /// `{{…}}` 一律按 JS 求值（到第一个 `}}` 为止，不配对），null 替换成空串；替换后为空时保留原地址。再处理页码列表。
  void _replaceKeyPageJs() {
    if (ruleUrl.contains('{{') && ruleUrl.contains('}}')) {
      final replaced = RuleSplitter(ruleUrl).innerRuleBetween('{{', '}}', (code) {
        final value = _eval(code);
        return value == null ? '' : valueToString(value);
      });
      if (replaced.isNotEmpty) ruleUrl = replaced;
    }
    final page = this.page;
    if (page != null) {
      for (final match in _pagePattern.allMatches(ruleUrl)) {
        final pages = match.group(1)!.split(',');
        // MD3 在 page=0 时越界，这里按第 1 页处理
        final chosen = page < pages.length ? pages[page < 1 ? 0 : page - 1] : pages.last;
        ruleUrl = ruleUrl.replaceAll(match.group(0)!, _trimJava(chosen));
      }
    }
  }

  void _analyzeUrl() {
    final urlMatch = _paramPattern.firstMatch(ruleUrl);
    final urlNoOption = urlMatch == null ? ruleUrl : ruleUrl.substring(0, urlMatch.start);
    url = absoluteUrlFrom(baseUrl, urlNoOption);
    final origin = _baseUrlOf(url);
    if (origin != null) baseUrl = origin;

    _method = 'GET';
    String? body;
    String? charset;
    _retry = 0;
    type = null;
    bodyJs = null;
    if (urlMatch != null) {
      final option = _parseOption(ruleUrl.substring(urlMatch.end));
      if (option != null) {
        if (option['method'] case final Object value) {
          _method = switch (_string(value).toUpperCase()) {
            'POST' => 'POST',
            'HEAD' => 'HEAD',
            _ => 'GET',
          };
        }
        for (final MapEntry(:key, :value) in _optionHeaders(option['headers']).entries) {
          headers[key] = value;
        }
        body = _optionBody(option['body']);
        type = switch (option['type']) {
          null => null,
          final Object value => _string(value),
        };
        charset = switch (option['charset']) {
          null => null,
          final Object value => _string(value),
        };
        final retryValue = option['retry'];
        _retry = retryValue is num ? retryValue.toInt() : 0;
        if (_useWebView(option['webView'])) throw NeedsWebViewException('"webView": ${jsonEncode(option['webView'])}');
        bodyJs = switch (option['bodyJs']) {
          null => null,
          final Object value => _string(value),
        };
        if (option['js'] case final Object js) {
          // result 是绝对地址，返回值不为 null 时作为新的地址
          final value = _eval(_string(js), result: url);
          if (value != null) url = valueToString(value);
        }
      }
    }

    _requestBody = null;
    _contentType = null;
    switch (_method) {
      case 'GET':
        final pos = url.indexOf('?');
        _requestUrl = pos == -1 ? url : '${url.substring(0, pos)}?${_encodeParams(url.substring(pos + 1), charset, isQuery: true)}';
      case 'HEAD':
        // OkHttp 的 get(urlNoQuery, null) 会清掉查询串
        final pos = url.indexOf('?');
        _requestUrl = pos == -1 ? url : url.substring(0, pos);
      default:
        _requestUrl = url;
        final contentType = headers['Content-Type'];
        String? encodedForm;
        if (body != null && !_isJson(body) && !_isXml(body) && (contentType == null || contentType.isEmpty)) {
          encodedForm = _encodeParams(body, charset, isQuery: false);
        }
        if ((encodedForm != null && encodedForm.isNotEmpty) || body == null || body.trim().isEmpty) {
          _contentType = 'application/x-www-form-urlencoded; charset=utf-8';
          _requestBody = encodedForm ?? '';
        } else if (contentType != null && contentType.trim().isNotEmpty) {
          // OkHttp 在没有 charset 的类型后面补上 utf-8，请求体按 UTF-8 发送
          _contentType = contentType.toLowerCase().contains('charset=') ? contentType : '$contentType; charset=utf-8';
          _requestBody = body;
        } else {
          _contentType = 'application/json; charset=UTF-8';
          _requestBody = body;
        }
    }
  }

  /// 要发出的请求。地址和请求体在构造地址时就编码好，请求头每次读取时取当前的值：
  /// MD3 发请求时才读 `headerMap`，`loginCheckJs` 里先改 `java.headerMap` 再 `java.getStrResponse()` 会带上新的请求头。
  HttpRequest get http {
    final requestHeaders = {...headers, if (_contentType case final contentType?) 'Content-Type': contentType};
    // User-Agent 的值是字面量 null 时不发送
    requestHeaders.removeWhere((name, value) => name.toLowerCase() == 'user-agent' && value == 'null');

    final source = task.source;
    return HttpRequest(
      url: _requestUrl,
      method: _method,
      headers: requestHeaders,
      body: _requestBody,
      sourceUrl: source.bookSourceUrl,
      enabledCookieJar: source.enabledCookieJar,
      concurrentRate: source.concurrentRate,
      retry: _retry,
      timeout: timeout,
    );
  }

  Object? _eval(String code, {Object? result}) => SourceJs.instance.evalUrl(this, code, result: result);

  /// URL 里 JS 结果转文本：null 是字符串 `null`。
  static String _text(Object? value) => value == null ? 'null' : valueToString(value);

  // ---------------------------------------------------------------- 请求

  /// 发出请求并处理响应（MD3 的 `getStrResponse`）：选项 `type` 不为 null 时正文是响应字节的十六进制，
  /// 否则解码正文，再执行 `bodyJs`（`result` 是正文，返回值转成文本，null 是 `null`）。
  /// 选项 `type` 不为 null 且地址是 `data:` 时不发请求（MD3 `getByteArrayIfDataUri`，fix-data-uri-request 设计 D1）。
  StrResponse fetch() {
    task.env.checkCancelled();
    if (type != null) {
      if (dataUriBytes(_urlNoQuery) case final bytes?) return StrResponse(url: url, body: hexEncode(bytes));
    }
    return response(task.env.fetch(http));
  }

  /// MD3 的 `urlNoQuery`：GET 请求去掉查询串，其它方法是整个地址。
  String get _urlNoQuery {
    final pos = url.indexOf('?');
    return _method == 'GET' && pos != -1 ? url.substring(0, pos) : url;
  }

  /// 处理一个已经拿到的响应，见 [fetch]。
  StrResponse response(HttpResult result) {
    if (type != null) return StrResponse(url: url, body: hexResponseBody(result));
    var body = decodeResponseBody(result);
    final js = bodyJs;
    if (js != null) body = _text(_eval(js, result: body));
    return StrResponse(
      url: result.url,
      body: body,
      statusCode: result.statusCode,
      headers: result.headers,
      setCookies: result.setCookies,
      redirected: result.redirected,
    );
  }

  // ---------------------------------------------------------------- 变量（URL 上下文的 java.put / java.get）

  /// 只写当前章节或本次链路的变量，两者都没有时丢弃。
  String put(String key, String value) {
    (chapter ?? ruleData)?.variables[key] = value;
    return value;
  }

  /// `bookName`、`title` 读书名和章节名；其余按章节、本次链路的顺序取第一个非空值，不读书源级变量。
  String get(String key) {
    if (key == 'bookName' && book != null) return book!.name;
    if (key == 'title' && chapter != null) return chapter!.title;
    for (final holder in [chapter, ruleData]) {
      final value = holder?.variables[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}

/// 照 MD3 构造请求，见 [SourceRequest]。
SourceRequest buildSourceRequest(
  SourceTask task,
  String mUrl, {
  String? key,
  int? page,
  String? baseUrl,
  RuleData? ruleData,
  ChapterData? chapter,
}) => SourceRequest(task, mUrl, key: key, page: page, baseUrl: baseUrl, ruleData: ruleData, chapter: chapter);

/// MD3 的 `BaseSource.getHeaderMap`：书源 `header` 以 `@js:` 或 `<js>` 开头（不区分大小写）时以书源级上下文执行，
/// 结果按严格或宽松 JSON 解析，解析失败或 JS 出错时只记日志；没有 User-Agent 时补默认值；再叠加登录头。
Map<String, String> sourceHeaders(SourceTask task) {
  final headers = <String, String>{};
  final header = task.source.header;
  if (header != null) {
    try {
      final lower = header.toLowerCase();
      final json = lower.startsWith('@js:')
          ? _jsText(SourceJs.instance.evalSource(task, header.substring(4)))
          : lower.startsWith('<js>')
          ? _jsText(SourceJs.instance.evalSource(task, header.substring(4, header.lastIndexOf('<'))))
          : header;
      headers.addAll(parseLenientStringMap(json));
    } on FormatException {
      // MD3 只记日志
    } on JsEvalException catch (e) {
      task.log('执行请求头规则出错\n$e', field: 'header');
    }
  }
  if (!headers.keys.any((name) => name.toLowerCase() == 'user-agent')) headers['User-Agent'] = defaultUserAgent;
  headers.addAll(task.loginHeaderMap ?? const {});
  return headers;
}

String _jsText(Object? value) => value == null ? 'null' : valueToString(value);

/// `data:…;base64,数据` 的字节（MD3 的 `dataUriRegex` 加 Android `Base64.DEFAULT`，fix-data-uri-request 设计 D2）；
/// 不是这种地址时为 null。数据不是合法 base64 时以 [FormatException] 结束。
Uint8List? dataUriBytes(String url) {
  final match = _dataUriPattern.firstMatch(url);
  return match == null ? null : base64DecodeAndroid(match.group(1)!, 0);
}

final RegExp _dataUriPattern = RegExp(r'^data:.*?;base64,(.*)');

/// MD3 的 `NetworkUtils.getBaseUrl`：http(s) 地址的协议加主机（和端口）部分。
String? _baseUrlOf(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) return null;
  final index = url.indexOf('/', 9);
  return index == -1 ? url : url.substring(0, index);
}

final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');
final RegExp _pagePattern = RegExp('<(.*?)>');
final RegExp _jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);

/// 选项按严格或宽松 JSON 解析成对象，失败时按没有选项处理。
Map<String, Object?>? _parseOption(String text) {
  try {
    final value = parseLenientJson(text);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

/// Gson 把字符串字段里的数字、布尔转成文本，对象转成 JSON。
String _string(Object value) => value is Map || value is List ? jsonEncode(value) : (value is double ? javaDoubleString(value) : '$value');

/// 选项里的 `headers`：对象，或内容为 JSON 对象的字符串。值按 Java 的 toString 转成文本。
Map<String, String> _optionHeaders(Object? headers) {
  Object? value = headers;
  if (value is String) {
    try {
      value = parseLenientJson(value);
    } on FormatException {
      return {};
    }
  }
  if (value is! Map) return {};
  return {for (final MapEntry(:key, value: v) in value.entries) '$key': _javaToString(v)};
}

/// 字符串原样使用；对象、数组、数字、布尔按 Gson（带缩进）序列化。
String? _optionBody(Object? body) => switch (body) {
  null => null,
  String() => body,
  _ => gsonPrettyJson(body),
};

/// MD3 的 `UrlOption.useWebView`：只有 null、空串、false、"false" 算假，数字 0 也算真。
bool _useWebView(Object? value) => !(value == null || value == '' || value == false || value == 'false');

/// Gson 解析出的值在 Java 里的 toString：对象 `{k=v}`，数组 `[a, b]`。
String _javaToString(Object? value) => switch (value) {
  null => 'null',
  double() => javaDoubleString(value),
  Map() => '{${value.entries.map((e) => '${e.key}=${_javaToString(e.value)}').join(', ')}}',
  List() => '[${value.map(_javaToString).join(', ')}]',
  _ => '$value',
};

bool _isJson(String text) {
  final trimmed = text.trim();
  return (trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'));
}

bool _isXml(String text) {
  final trimmed = text.trim();
  return trimmed.startsWith('<') && trimmed.endsWith('>');
}

// ---------------------------------------------------------------- 参数编码

/// MD3 的 `AnalyzeUrl.encodeParams`。
/// 查询串：已经是合法编码时原样返回，否则逐字符编码（`escape` 时逐个参数按 JS escape 编码）。
/// 表单：逐个参数用 `URLEncoder` 编码；没有指定 charset 时跳过已经编码过的值。
String _encodeParams(String params, String? charset, {required bool isQuery}) {
  final checkEncoded = charset == null || charset.isEmpty;
  final Encoding? encoding;
  if (checkEncoded) {
    encoding = utf8;
  } else if (charset == 'escape') {
    encoding = null;
  } else {
    encoding = charsetByName(charset) ?? (throw RuleException('不支持的编码：$charset'));
  }
  if (isQuery && encoding != null) {
    if (_isEncodedQuery(params)) return params;
    return _encodeQueryParams(params, encoding);
  }
  final out = StringBuffer();
  var pos = 0;
  while (pos <= params.length) {
    if (out.isNotEmpty) out.write('&');
    var amp = params.indexOf('&', pos);
    if (amp == -1) amp = params.length;
    final eq = params.indexOf('=', pos);
    String key;
    String? value;
    if (eq == -1 || eq > amp) {
      key = params.substring(pos, amp);
    } else {
      key = params.substring(pos, eq);
      value = params.substring(eq + 1, amp);
    }
    _appendEncoded(out, key, checkEncoded, encoding);
    if (value != null) {
      out.write('=');
      _appendEncoded(out, value, checkEncoded, encoding);
    }
    pos = amp + 1;
  }
  return out.toString();
}

void _appendEncoded(StringBuffer out, String value, bool checkEncoded, Encoding? encoding) {
  if (checkEncoded && _isEncodedForm(value)) {
    out.write(value);
  } else if (encoding == null) {
    out.write(_jsEscape(value));
  } else {
    out.write(urlEncodeLikeJava(value, encoding));
  }
}

const String _hexUpper = '0123456789ABCDEF';

/// 查询串编码时保留的字符。
final Set<int> _querySafe = r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~!$%&()*+,/:;=?@[\]^`{|}".codeUnits.toSet();

/// 逐个 UTF-16 单元编码：安全字符保留，其余转成字节后输出大写的 `%XX`。
String _encodeQueryParams(String text, Encoding encoding) {
  final out = StringBuffer();
  for (final c in text.codeUnits) {
    if (c < 128 && _querySafe.contains(c)) {
      out.writeCharCode(c);
      continue;
    }
    for (final b in encodeLikeJava(String.fromCharCode(c), encoding)) {
      out
        ..write('%')
        ..write(_hexUpper[b >> 4])
        ..write(_hexUpper[b & 0xF]);
    }
  }
  return out.toString();
}

/// JS 的 `escape()`（MD3 的 `EncoderUtils.escape`）：字母数字保留，其余输出小写十六进制的 `%XX` 或 `%uXXXX`。
String _jsEscape(String text) {
  final out = StringBuffer();
  for (final c in text.codeUnits) {
    if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
      out.writeCharCode(c);
      continue;
    }
    out
      ..write(c < 16 ? '%0' : (c < 256 ? '%' : '%u'))
      ..write(c.toRadixString(16));
  }
  return out.toString();
}

final Set<int> _encodedQueryChars = r"!$&()*+,-./:;=?@[\]^_`{|}~".codeUnits.toSet();

/// MD3 的 `NetworkUtils.encodedQuery`：只含不需要编码的字符和合法的 `%XX`。
bool _isEncodedQuery(String text) => _isEncoded(text, (c) => _isAlnum(c) || _encodedQueryChars.contains(c));

/// MD3 的 `NetworkUtils.encodedForm`。
bool _isEncodedForm(String text) => _isEncoded(text, (c) => _isAlnum(c) || c == 0x2A || c == 0x2D || c == 0x2E || c == 0x5F);

bool _isEncoded(String text, bool Function(int) safe) {
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (safe(c)) {
      i++;
      continue;
    }
    if (c == 0x25 && i + 2 < text.length && _isHex(text.codeUnitAt(i + 1)) && _isHex(text.codeUnitAt(i + 2))) {
      i += 3;
      continue;
    }
    return false;
  }
  return true;
}

bool _isAlnum(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

bool _isHex(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

String _trimJava(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  return text.substring(start, end);
}
