import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;

import '../core/environment.dart';
import '../html/css_selector.dart';
import '../text/charsets.dart';
import '../text/gbk.dart';

/// 把响应解码成文本，照 MD3 的 `ResponseBody.text()` 和 `AnalyzeUrl` 的后处理：
/// 1. 去掉 UTF-8 BOM；
/// 2. 用响应头 Content-Type 里的 charset；
/// 3. 用 HTML `<meta>` 声明的 charset；
/// 4. 都没有时，字节是合法 UTF-8 就按 UTF-8 解码，否则按 GBK（MD3 用 ICU 检测，D12）。
/// 编码名称无法识别时按没有声明处理。Content-Type 是 XML 而正文没有 XML 声明时，前面补上 `<?xml version="1.0"?>`。
String decodeResponseBody(HttpResult result) {
  var bytes = result.body;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    bytes = Uint8List.sublistView(bytes, 3);
  }
  final contentType = result.headers['content-type'];
  final encoding = _headerCharset(contentType) ?? _metaCharset(bytes) ?? _guess(bytes);
  final text = identical(encoding, utf8) ? utf8.decode(bytes, allowMalformed: true) : encoding.decode(bytes);
  if (contentType != null && _xmlContentType.hasMatch(contentType) && !text.trim().toLowerCase().startsWith('<?xml')) {
    return '<?xml version="1.0"?>$text';
  }
  return text;
}

/// 选项 `type` 不为 null 时的结果：响应字节的小写十六进制。
String hexResponseBody(HttpResult result) =>
    result.body.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final RegExp _xmlContentType = RegExp(r'^(application|text)/\w*\+?xml.*$');

/// OkHttp 的 `MediaType.charset()`：参数名不区分大小写，值可以带引号。
Encoding? _headerCharset(String? contentType) {
  if (contentType == null) return null;
  for (final parameter in contentType.split(';').skip(1)) {
    final eq = parameter.indexOf('=');
    if (eq < 0 || parameter.substring(0, eq).trim().toLowerCase() != 'charset') continue;
    var value = parameter.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
    return charsetByName(value);
  }
  return null;
}

final List<int> _headOpen = ascii.encode('<head>');
final List<int> _headClose = ascii.encode('</head>');
final RegExp _headTag = RegExp(r'<head>[\s\S]*?</head>', caseSensitive: false);

/// MD3 的 `EncodingDetect.getHtmlEncode`：在 `<head>` 里找 meta 的 charset，
/// 或 `http-equiv="content-type"` 的 content 里的 charset。
Encoding? _metaCharset(Uint8List bytes) {
  String? head;
  final start = _indexOf(bytes, _headOpen, 0);
  if (start > -1) {
    final end = _indexOf(bytes, _headClose, start);
    if (end > -1) head = utf8.decode(bytes.sublist(start, end + _headClose.length), allowMalformed: true);
  }
  head ??= _headTag.firstMatch(utf8.decode(bytes, allowMalformed: true))?.group(0);
  if (head == null) return null;

  final fragment = html_parser.parseFragment(head);
  for (final meta in fragment.querySelectorAll('meta')) {
    final charset = jsoupAttr(meta, 'charset');
    if (charset.isNotEmpty) return charsetByName(charset);
    if (jsoupAttr(meta, 'http-equiv').toLowerCase() == 'content-type') {
      final content = jsoupAttr(meta, 'content');
      final index = content.toLowerCase().indexOf('charset=');
      // 没有 charset= 时 MD3 取分号之后（没有分号时是整个 content），当编码名会出错，这里按没有声明处理（D12）
      final name = index > -1 ? content.substring(index + 'charset='.length) : _substringAfter(content, ';');
      if (name.isNotEmpty) return charsetByName(name);
    }
  }
  return null;
}

String _substringAfter(String text, String delimiter) {
  final index = text.indexOf(delimiter);
  return index < 0 ? text : text.substring(index + delimiter.length);
}

/// 合法 UTF-8 按 UTF-8，否则按 GBK。
Encoding _guess(Uint8List bytes) {
  try {
    utf8.decode(bytes);
    return utf8;
  } on FormatException {
    return gbk;
  }
}

int _indexOf(Uint8List bytes, List<int> pattern, int from) {
  outer:
  for (var i = from; i <= bytes.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
