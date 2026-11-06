// 只复用 HTML5 实体数据；tokenizer 的最长前缀、NUL 与属性规则不同于 jsoup。
// ignore: implementation_imports
import 'package:html/src/constants.dart' show entities, replacementCharacters;

/// jsoup 1.16.2 `Parser.unescapeEntities`，只解实体，不解析标签、不规范化换行。
String unescapeJsoupEntities(String text, bool inAttribute) {
  var start = 0;
  var amp = text.indexOf('&');
  if (amp < 0) return text;
  final out = StringBuffer();
  while (amp >= 0) {
    out.write(text.substring(start, amp));
    final decoded = _reference(text, amp + 1, inAttribute);
    if (decoded == null) {
      out.write('&');
      start = amp + 1;
    } else {
      out.write(decoded.$1);
      start = decoded.$2;
    }
    amp = text.indexOf('&', start);
  }
  out.write(text.substring(start));
  return out.toString();
}

(String, int)? _reference(String text, int start, bool inAttribute) {
  if (start >= text.length) return null;
  if (text.codeUnitAt(start) == 0x23) {
    final match = _number.matchAsPrefix(text, start);
    if (match == null) return null;
    final hex = match.group(1);
    var value = int.tryParse(
      hex ?? match.group(2)!,
      radix: hex == null ? 10 : 16,
    );
    if (value == null ||
        value > 0x10FFFF ||
        (value >= 0xD800 && value <= 0xDFFF)) {
      value = 0xFFFD;
    }
    // jsoup 只映射 Windows-1252 的 0x80..0x9F；与 HTML5 tokenizer 不同，0 保留为 NUL。
    final decoded = value >= 0x80 && value <= 0x9F
        ? replacementCharacters[value]!
        : String.fromCharCode(value);
    return (decoded, match.end);
  }

  // CharacterReader.consumeLetterThenDigitSequence：先吃完整字母串，再吃数字，不回退到已知前缀。
  var end = start;
  while (end < text.length && _isLetter(text.codeUnitAt(end))) {
    end++;
  }
  while (end < text.length && _isDigit(text.codeUnitAt(end))) {
    end++;
  }
  final name = text.substring(start, end);
  final semicolon = end < text.length && text.codeUnitAt(end) == 0x3B;
  final decoded = entities[semicolon ? '$name;' : name];
  if (decoded == null) return null;
  if (inAttribute && !semicolon && end < text.length) {
    final next = text.codeUnitAt(end);
    if (_isLetter(next) ||
        _isDigit(next) ||
        next == 0x3D ||
        next == 0x2D ||
        next == 0x5F) {
      return null;
    }
  }
  return (decoded, end + (semicolon ? 1 : 0));
}

final RegExp _number = RegExp(r'#(?:[xX]([0-9a-fA-F]+)|([0-9]+));?');
final RegExp _letter = RegExp(r'^\p{L}$', unicode: true);

// Java Character.isLetter(char) 检查 UTF-16 单元，补充平面的代理项不算字母。
bool _isLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit > 0x7F && _letter.hasMatch(String.fromCharCode(unit)));

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
