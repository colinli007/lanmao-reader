import 'dart:convert';

import '../core/environment.dart';
import '../core/errors.dart';
import '../json/json_text.dart';
import '../net/java_url.dart';
import '../rule/rule_splitter.dart';
import '../source/book_source.dart';
import '../text/charsets.dart';
import '../text/gson_json.dart';
import '../text/lenient_json.dart';

/// 书源没有 User-Agent 时补的默认值（MD3 用桌面 Chrome 的 UA）。
const String defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 构造好的请求：MD3 的 `AnalyzeUrl` 去掉网络的部分。网络在主 isolate 上执行，Cookie 和限速也在那边。
final class SourceRequest {
  const SourceRequest({required this.ruleUrl, required this.url, required this.http, this.type});

  /// 替换模板之后的地址（含 `,{选项}`）。
  final String ruleUrl;

  /// 绝对地址，不含选项。链路把它当作请求的地址（`baseUrl`）。
  final String url;

  /// 选项里的 `type`：不为 null 时结果是响应字节的十六进制字符串。
  final String? type;

  final HttpRequest http;
}

/// 照 MD3 的 `AnalyzeUrl` 构造请求：
/// 1. 地址里有 `@js:`、`<js>` 时需要 JS；
/// 2. 替换 `{{key}}`、`{{page}}`、`{{baseUrl}}`，其余 `{{}}` 需要 JS；
/// 3. 处理 `<a,b,c>` 页码列表；
/// 4. 切出 `,{选项}`，地址按 [baseUrl] 转成绝对地址；
/// 5. 按选项和书源请求头构造请求，编码查询串或表单。
SourceRequest buildSourceRequest(String mUrl, {String? key, int? page, String baseUrl = '', BookSource? source}) {
  var base = baseUrl;
  final optionMatch = _paramPattern.firstMatch(base);
  if (optionMatch != null) base = base.substring(0, optionMatch.start);
  final headers = source == null ? <String, String>{} : sourceHeaders(source);
  headers.remove('proxy');

  final jsMatch = _jsPattern.firstMatch(mUrl);
  if (jsMatch != null) throw NeedsJsException(jsMatch.group(0)!);
  var ruleUrl = _replaceKeyPage(mUrl, key: key, page: page, baseUrl: base);

  final urlMatch = _paramPattern.firstMatch(ruleUrl);
  final urlNoOption = urlMatch == null ? ruleUrl : ruleUrl.substring(0, urlMatch.start);
  var url = absoluteUrlFrom(base, urlNoOption);

  var method = 'GET';
  String? body;
  String? type;
  String? charset;
  var retry = 0;
  if (urlMatch != null) {
    final option = _parseOption(ruleUrl.substring(urlMatch.end));
    if (option != null) {
      if (option['method'] case final Object value) {
        method = switch (_string(value).toUpperCase()) {
          'POST' => 'POST',
          'HEAD' => 'HEAD',
          _ => 'GET',
        };
      }
      for (final MapEntry(:key, :value) in _optionHeaders(option['headers']).entries) {
        headers[key] = value;
      }
      body = _optionBody(option['body']) ?? body;
      type = switch (option['type']) {
        null => null,
        final Object value => _string(value),
      };
      charset = switch (option['charset']) {
        null => null,
        final Object value => _string(value),
      };
      final retryValue = option['retry'];
      retry = retryValue is num ? retryValue.toInt() : 0;
      if (_useWebView(option['webView'])) throw NeedsWebViewException('"webView": ${jsonEncode(option['webView'])}');
      if (option['js'] case final Object js) throw NeedsJsException('"js": ${_string(js)}');
      if (option['bodyJs'] case final Object js) throw NeedsJsException('"bodyJs": ${_string(js)}');
    }
  }

  String requestUrl;
  String? requestBody;
  switch (method) {
    case 'GET':
      final pos = url.indexOf('?');
      requestUrl = pos == -1 ? url : '${url.substring(0, pos)}?${_encodeParams(url.substring(pos + 1), charset, isQuery: true)}';
    case 'HEAD':
      // OkHttp 的 get(urlNoQuery, null) 会清掉查询串
      final pos = url.indexOf('?');
      requestUrl = pos == -1 ? url : url.substring(0, pos);
    default:
      requestUrl = url;
      final contentType = headers['Content-Type'];
      String? encodedForm;
      if (body != null && !_isJson(body) && !_isXml(body) && (contentType == null || contentType.isEmpty)) {
        encodedForm = _encodeParams(body, charset, isQuery: false);
      }
      if ((encodedForm != null && encodedForm.isNotEmpty) || body == null || body.trim().isEmpty) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
        requestBody = encodedForm ?? '';
      } else if (contentType != null && contentType.trim().isNotEmpty) {
        // OkHttp 在没有 charset 的类型后面补上 utf-8，请求体按 UTF-8 发送
        headers['Content-Type'] = contentType.toLowerCase().contains('charset=') ? contentType : '$contentType; charset=utf-8';
        requestBody = body;
      } else {
        headers['Content-Type'] = 'application/json; charset=UTF-8';
        requestBody = body;
      }
  }
  // User-Agent 的值是字面量 null 时不发送
  headers.removeWhere((name, value) => name.toLowerCase() == 'user-agent' && value == 'null');

  return SourceRequest(
    ruleUrl: ruleUrl,
    url: url,
    type: type,
    http: HttpRequest(
      url: requestUrl,
      method: method,
      headers: headers,
      body: requestBody,
      sourceUrl: source?.bookSourceUrl ?? url,
      enabledCookieJar: source?.enabledCookieJar ?? false,
      concurrentRate: source?.concurrentRate,
      retry: retry,
    ),
  );
}

/// MD3 的 `BaseSource.getHeaderMap`：书源 `header` 按严格或宽松 JSON 解析，解析失败时为空；没有 User-Agent 时补默认值。
Map<String, String> sourceHeaders(BookSource source) {
  final headers = <String, String>{};
  final header = source.header;
  if (header != null) {
    final lower = header.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('<js>')) throw NeedsJsException(header);
    try {
      headers.addAll(parseLenientStringMap(header));
    } on FormatException {
      // MD3 只记日志
    }
  }
  if (!headers.keys.any((name) => name.toLowerCase() == 'user-agent')) headers['User-Agent'] = defaultUserAgent;
  return headers;
}

final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');
final RegExp _pagePattern = RegExp('<(.*?)>');
final RegExp _jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);

/// 替换 `{{}}`（只认 key、page、baseUrl）和 `<a,b,c>` 页码列表。
String _replaceKeyPage(String ruleUrl, {String? key, int? page, required String baseUrl}) {
  var url = ruleUrl;
  if (url.contains('{{') && url.contains('}}')) {
    final replaced = RuleSplitter(url).innerRuleBetween('{{', '}}', (expression) {
      return switch (expression.trim()) {
        'key' => key ?? '',
        'page' => page?.toString() ?? '',
        'baseUrl' => baseUrl,
        _ => throw NeedsJsException('{{$expression}}'),
      };
    });
    if (replaced.isNotEmpty) url = replaced;
  }
  if (page != null) {
    for (final match in _pagePattern.allMatches(url)) {
      final pages = match.group(1)!.split(',');
      // MD3 在 page=0 时越界，这里按第 1 页处理
      final chosen = page < pages.length ? pages[page < 1 ? 0 : page - 1] : pages.last;
      url = url.replaceAll(match.group(0)!, _trimJava(chosen));
    }
  }
  return url;
}

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
    out.write(_urlEncode(value, encoding));
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

/// Java `URLEncoder.encode`：字母数字和 `.-*_` 保留，空格转成 `+`，其余按字符集转成大写的 `%XX`。
String _urlEncode(String text, Encoding encoding) {
  final out = StringBuffer();
  final runes = text.runes.toList();
  var i = 0;
  while (i < runes.length) {
    final c = runes[i];
    if (_isFormSafe(c)) {
      out.writeCharCode(c);
      i++;
    } else if (c == 0x20) {
      out.write('+');
      i++;
    } else {
      // 连续的需要编码的字符一起转成字节
      final start = i;
      while (i < runes.length && !_isFormSafe(runes[i]) && runes[i] != 0x20) {
        i++;
      }
      for (final b in encodeLikeJava(String.fromCharCodes(runes.sublist(start, i)), encoding)) {
        out
          ..write('%')
          ..write(_hexUpper[b >> 4])
          ..write(_hexUpper[b & 0xF]);
      }
    }
  }
  return out.toString();
}

bool _isFormSafe(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2E || c == 0x2D || c == 0x2A || c == 0x5F;

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
