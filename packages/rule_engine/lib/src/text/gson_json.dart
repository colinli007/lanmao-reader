import '../json/json_text.dart';

/// MD3 的 `GSON.toJson`：开了 PrettyPrinting（两个空格缩进）、关了 HTML 转义，对象里值为 null 的键省略。
/// 整数按整数输出，小数按 Java 的 `Double.toString` 输出。
String gsonPrettyJson(Object? value) {
  final out = StringBuffer();
  void write(Object? current, int depth) {
    switch (current) {
      case null:
        out.write('null');
      case String():
        _writeString(out, current);
      case double():
        out.write(javaDoubleString(current));
      case Map():
        final entries = current.entries.where((entry) => entry.value != null).toList();
        if (entries.isEmpty) {
          out.write('{}');
          return;
        }
        out.write('{');
        for (var i = 0; i < entries.length; i++) {
          out
            ..write(i == 0 ? '\n' : ',\n')
            ..write('  ' * (depth + 1));
          _writeString(out, '${entries[i].key}');
          out.write(': ');
          write(entries[i].value, depth + 1);
        }
        out
          ..write('\n')
          ..write('  ' * depth)
          ..write('}');
      case List():
        if (current.isEmpty) {
          out.write('[]');
          return;
        }
        out.write('[');
        for (var i = 0; i < current.length; i++) {
          out
            ..write(i == 0 ? '\n' : ',\n')
            ..write('  ' * (depth + 1));
          write(current[i], depth + 1);
        }
        out
          ..write('\n')
          ..write('  ' * depth)
          ..write(']');
      default:
        out.write('$current');
    }
  }

  write(value, 0);
  return out.toString();
}

/// Gson 的 JsonWriter（关了 HTML 转义）：转义引号、反斜杠、控制字符和 U+2028、U+2029。
void _writeString(StringBuffer out, String text) {
  out.write('"');
  for (final c in text.codeUnits) {
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x0C:
        out.write(r'\f');
      case 0x2028 || 0x2029:
        out.write('\\u${c.toRadixString(16)}');
      default:
        if (c < 0x20) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}
