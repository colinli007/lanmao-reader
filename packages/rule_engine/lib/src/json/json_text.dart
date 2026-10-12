/// MD3 里 JSON 值转字符串的方式。
///
/// MD3 用 json-path 3.0.0 + json-smart 2.6.0 读 JSON：对象是 Java `LinkedHashMap`，`toString` 是 `{k=v, k2=v2}`；
/// 数组是 json-smart 的 `JSONArray`，`toString` 是紧凑 JSON；小数是 Java `Double`，按 `Double.toString` 输出。
library;

/// 对象 `{k=v, ...}`，数组紧凑 JSON，数字和布尔按 Java 的 `toString`，null 为 `null`。
String jaywayString(Object? value) => switch (value) {
  null => 'null',
  String() => value,
  double() => javaDoubleString(value),
  Map() => _mapString(value),
  List() => jsonSmartString(value),
  _ => '$value',
};

/// Java `AbstractMap.toString`。
String _mapString(Map<Object?, Object?> map) =>
    '{${map.entries.map((entry) => '${entry.key}=${jaywayString(entry.value)}').join(', ')}}';

/// json-smart 的 `JSONValue.toJSONString`（默认风格）：紧凑 JSON，不转义 `/`，
/// 控制字符、U+007F 到 U+009F、U+2000 到 U+20FF 输出成 `\uXXXX`。
String jsonSmartString(Object? value) {
  final out = StringBuffer();
  void write(Object? current) {
    switch (current) {
      case null:
        out.write('null');
      case String():
        out.write('"');
        _escape(out, current);
        out.write('"');
      case double():
        out.write(_jsonSmartDouble(current));
      case Map():
        out.write('{');
        var first = true;
        for (final entry in current.entries) {
          if (!first) out.write(',');
          first = false;
          out.write('"');
          _escape(out, '${entry.key}');
          out.write('":');
          write(entry.value);
        }
        out.write('}');
      case List():
        out.write('[');
        for (var i = 0; i < current.length; i++) {
          if (i > 0) out.write(',');
          write(current[i]);
        }
        out.write(']');
      default:
        out.write('$current');
    }
  }

  write(value);
  return out.toString();
}

// json-smart 写 Double 时用 Double.toString
String _jsonSmartDouble(double value) => value.isFinite ? javaDoubleString(value) : 'null';

void _escape(StringBuffer out, String text) {
  for (final c in text.codeUnits) {
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (c <= 0x1F || (c >= 0x7F && c <= 0x9F) || (c >= 0x2000 && c <= 0x20FF)) {
          out.write('\\u${c.toRadixString(16).toUpperCase().padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
}

/// Java `Double.toString`：绝对值在 [1e-3, 1e7) 时用小数形式（至少一位小数），否则用 `d.dddE±n`。
String javaDoubleString(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == 0) return value.isNegative ? '-0.0' : '0.0';
  final magnitude = value.abs();
  if (magnitude >= 1e-3 && magnitude < 1e7) {
    final text = value.toString();
    return text.contains('.') ? text : '$text.0';
  }
  // Dart 的 toStringAsExponential() 给出最短的有效数字，如 1.5e+20
  final exponential = value.toStringAsExponential();
  final [mantissa, exponent] = exponential.split('e');
  final digits = mantissa.contains('.') ? mantissa : '$mantissa.0';
  return '${digits}E${int.parse(exponent)}';
}
