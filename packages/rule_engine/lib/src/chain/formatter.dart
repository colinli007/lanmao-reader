/// MD3 链路里的格式化：`HtmlFormatter`、`BookHelp.formatBookName/formatBookAuthor`、`StringUtils.wordCountFormat`、
/// `String.isTrue`。这些是引擎自己的固定正则，用 Dart [RegExp]。
///
/// MD3 跑在 Android 上，`java.util.regex` 底层是 ICU：`\s` 包含全角空格 U+3000 等 Unicode 空白，
/// 和 Dart（JS）的 `\s` 基本一致，所以这里直接用 `\s`。
library;

import 'dart:typed_data';

import '../net/java_url.dart';

final RegExp _nbsp = RegExp('(&nbsp;)+');
final RegExp _esp = RegExp('(&ensp;|&emsp;)');
final RegExp _noPrint = RegExp('(&thinsp;|&zwnj;|&zwj;| |‌|‍)');
final RegExp _wrapHtml = RegExp(r'</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>');
final RegExp _comment = RegExp('<!--[^>]*-->');
final RegExp _notImgHtml = RegExp(r'</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>');
final RegExp _otherHtml = RegExp(r'</?[a-zA-Z]+(?=[ >])[^<>]*>');
final RegExp _indent1 = RegExp(r'\s*\n+\s*');
final RegExp _indent2 = RegExp(r'^[\n\s]+');
final RegExp _last = RegExp(r'[\n\s]+$');
final RegExp _formatImage = RegExp(
  r"""<img[^>]*\ssrc\s*=\s*['"]([^'"{>]*\{(?:[^{}]|\{[^}>]+\})+\})['"][^>]*>|<img[^>]*\s(?:data-src|src)\s*=\s*['"]([^'">]+)['"][^>]*>|<img[^>]*\sdata-[^=>]*=\s*['"]([^'">]*)['"][^>]*>""",
  caseSensitive: false,
);
final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');

const String paragraphIndent = '　　';

/// `HtmlFormatter.format`：空白实体转空格，去掉零宽字符和注释，块级标签转换行，去掉其余标签，每段行首加两个全角空格。
String formatHtml(String? html) => _format(html, _otherHtml);

String _format(String? html, RegExp otherRegex) {
  if (html == null) return '';
  return html
      .replaceAll(_nbsp, ' ')
      .replaceAll(_esp, ' ')
      .replaceAll(_noPrint, '')
      .replaceAll(_wrapHtml, '\n')
      .replaceAll(_comment, '')
      .replaceAll(otherRegex, '')
      .replaceAll(_indent1, '\n$paragraphIndent')
      .replaceAll(_indent2, paragraphIndent)
      .replaceAll(_last, '');
}

/// `HtmlFormatter.formatKeepImg`：同 [formatHtml] 但保留 img，img 的地址转成绝对地址（保留 `,{选项}`）。
String formatKeepImg(String? html, JavaUrl? redirectUrl) {
  if (html == null) return '';
  final keepImgHtml = _format(html, _notImgHtml);
  final out = StringBuffer();
  var appendPos = 0;
  for (final match in _formatImage.allMatches(keepImgHtml)) {
    var param = '';
    String url;
    if (match.group(1) case final withOption?) {
      final option = _paramPattern.firstMatch(withOption);
      if (option != null) {
        param = ',${withOption.substring(option.end)}';
        url = withOption.substring(0, option.start);
      } else {
        url = withOption;
      }
    } else {
      url = match.group(2) ?? match.group(3)!;
    }
    out
      ..write(keepImgHtml.substring(appendPos, match.start))
      ..write('<img src="${absoluteUrl(redirectUrl, url)}$param">');
    appendPos = match.end;
  }
  if (appendPos < keepImgHtml.length) out.write(keepImgHtml.substring(appendPos));
  return out.toString();
}

final RegExp _name = RegExp(r'\s+作\s*者.*|\s+\S+\s+著');
final RegExp _author = RegExp(r'^\s*作\s*者[:：\s]+|\s+著');

/// `BookHelp.formatBookName`：去掉「作者」等后缀。
String formatBookName(String name) => _trimJava(name.replaceAll(_name, ''));

/// `BookHelp.formatBookAuthor`：去掉「作者：」前缀和「著」后缀。
String formatBookAuthor(String author) => _trimJava(author.replaceAll(_author, ''));

final RegExp _numeric = RegExp(r'^-?[0-9]+$');

/// `StringUtils.wordCountFormat`：纯整数时，大于 1 万为「x.x万字」，1 到 1 万为「x字」，不大于 0 为空；不是纯整数时原样返回。
/// 整数超出 Int 范围时 MD3 抛 NumberFormatException（调用方吞掉），这里抛 [FormatException]。
String wordCountFormat(String? wc) {
  if (wc == null) return '';
  if (!_numeric.hasMatch(wc)) return wc;
  final words = int.parse(wc);
  if (words > 0x7FFFFFFF || words < -0x80000000) throw FormatException('字数超出范围', wc);
  if (words <= 0) return '';
  if (words <= 10000) return '$words字';
  // words * 1.0f：先转成 float；DecimalFormat("#.#") 按十进制值四舍六入五成双
  final asFloat = (Float32List(1)..[0] = words.toDouble())[0].toInt();
  var tenths = asFloat ~/ 1000;
  final rest = asFloat % 1000;
  if (rest > 500 || (rest == 500 && tenths.isOdd)) tenths++;
  return '${tenths ~/ 10}${tenths % 10 == 0 ? '' : '.${tenths % 10}'}万字';
}

final RegExp _falsy = RegExp(r'^(?:false|no|not|0|0.0)$', caseSensitive: false);

/// MD3 的 `String.isTrue()`：空白和 `null` 为假，`false`、`no`、`not`、`0`、`0.0`（不区分大小写）为假，其余为真。
bool isTrue(String? text) {
  if (text == null || text.trim().isEmpty || text == 'null') return false;
  return !_falsy.hasMatch(text.trim());
}

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
