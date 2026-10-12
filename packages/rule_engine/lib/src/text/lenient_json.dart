import 'dart:convert';

/// 按 Gson 宽松模式解析 JSON，MD3 解析书源 `header` 和 URL 选项时，严格解析失败就用它。
///
/// 在标准 JSON 之外接受：单引号字符串、不带引号的键和值、`=` / `=>` 作键值分隔、`;` 作元素分隔、
/// `//`、`#`、`/* */` 注释，数组里多余的逗号按 null 处理。和 Gson 一样，对象末尾多一个逗号仍然是错误。
/// 整数解析为 [int]，其余数字为 [double]。不合法时抛出 [FormatException]。
Object? parseLenientJson(String text) {
  final parser = _LenientJsonParser(text);
  final value = parser.readValue();
  parser.skipBlank();
  if (!parser.atEnd) parser.fail('JSON 后面还有多余内容');
  return value;
}

/// 解析成字符串映射，值按 MD3 的 `StringJsonDeserializer` 转换：
/// 字符串、数字、布尔原样转成文本，null 丢弃，对象和数组转成紧凑 JSON。顶层不是对象时抛出 [FormatException]。
Map<String, String> parseLenientStringMap(String text) {
  final value = parseLenientJson(text);
  if (value is! Map<String, Object?>) throw FormatException('不是 JSON 对象', text);
  return {
    for (final MapEntry(:key, :value) in value.entries)
      if (value != null) key: jsonText(value),
  };
}

/// 把 JSON 值转成 MD3 里的字符串：原始值取文本，对象和数组取紧凑 JSON。
String jsonText(Object value) => value is Map || value is List ? jsonEncode(value) : '$value';

final class _LenientJsonParser {
  _LenientJsonParser(this.text);

  final String text;
  int pos = 0;

  bool get atEnd => pos >= text.length;

  Never fail(String message) => throw FormatException(message, text, pos);

  Object? readValue() {
    skipBlank();
    if (atEnd) fail('缺少 JSON 值');
    return switch (text[pos]) {
      '{' => _readObject(),
      '[' => _readArray(),
      '"' || "'" => _readQuoted(),
      _ => _readLiteral(),
    };
  }

  Map<String, Object?> _readObject() {
    pos++;
    final map = <String, Object?>{};
    skipBlank();
    if (_take('}')) return map;
    while (true) {
      skipBlank();
      if (atEnd) fail('对象没有结束');
      final char = text[pos];
      if (char == '}' || char == ',' || char == ';') fail('缺少键名');
      final key = char == '"' || char == "'" ? _readQuoted() : _readUnquoted();
      skipBlank();
      if (!_take(':') && !_take('=')) fail('缺少键值分隔符');
      _take('>');
      map[key] = readValue();
      skipBlank();
      if (_take(',') || _take(';')) continue;
      if (_take('}')) return map;
      fail('对象里缺少逗号或右括号');
    }
  }

  List<Object?> _readArray() {
    pos++;
    final list = <Object?>[];
    skipBlank();
    if (_take(']')) return list;
    while (true) {
      skipBlank();
      if (atEnd) fail('数组没有结束');
      final char = text[pos];
      // 多余的分隔符：Gson 宽松模式按省略了一个 null 处理
      if (char == ',' || char == ';' || char == ']') {
        list.add(null);
      } else {
        list.add(readValue());
        skipBlank();
      }
      if (_take(',') || _take(';')) continue;
      if (_take(']')) return list;
      fail('数组里缺少逗号或右括号');
    }
  }

  String _readQuoted() {
    final quote = text[pos++];
    final out = StringBuffer();
    while (!atEnd) {
      final char = text[pos++];
      if (char == quote) return out.toString();
      if (char != r'\') {
        out.write(char);
        continue;
      }
      if (atEnd) break;
      final escaped = text[pos++];
      switch (escaped) {
        case 'u':
          if (pos + 4 > text.length) fail('\\u 转义不完整');
          final code = int.tryParse(text.substring(pos, pos + 4), radix: 16) ?? fail('\\u 转义不合法');
          out.writeCharCode(code);
          pos += 4;
        case 't':
          out.write('\t');
        case 'b':
          out.write('\b');
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 'f':
          out.write('\f');
        case '\n' || "'" || '"' || r'\' || '/':
          out.write(escaped);
        default:
          fail('不合法的转义');
      }
    }
    fail('字符串没有结束');
  }

  Object? _readLiteral() {
    final literal = _readUnquoted();
    if (literal.isEmpty) fail('缺少 JSON 值');
    switch (literal.toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    if (_number.hasMatch(literal)) {
      return int.tryParse(literal) ?? double.parse(literal);
    }
    return literal;
  }

  /// 不带引号的键或值，到分隔符、空白或注释为止（Gson 的 `isLiteral`）。
  String _readUnquoted() {
    final start = pos;
    while (!atEnd && !_literalEnd.contains(text[pos])) {
      pos++;
    }
    return text.substring(start, pos);
  }

  /// 跳过空白和注释。
  void skipBlank() {
    while (!atEnd) {
      final char = text[pos];
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        pos++;
      } else if (char == '#' || text.startsWith('//', pos)) {
        final end = text.indexOf('\n', pos);
        pos = end < 0 ? text.length : end + 1;
      } else if (text.startsWith('/*', pos)) {
        final end = text.indexOf('*/', pos + 2);
        if (end < 0) fail('注释没有结束');
        pos = end + 2;
      } else {
        return;
      }
    }
  }

  bool _take(String char) {
    if (atEnd || text[pos] != char) return false;
    pos++;
    return true;
  }

  static const Set<String> _literalEnd = {
    '/', r'\', ';', '#', '=', '{', '}', '[', ']', ':', ',', ' ', '\t', '\f', '\r', '\n', //
  };

  static final RegExp _number = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$');
}
