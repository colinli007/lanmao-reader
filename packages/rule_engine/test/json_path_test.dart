import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/json/json_path.dart';
import 'package:rule_engine/src/json/json_text.dart';
import 'package:test/test.dart';

// 期望值由 Jayway json-path 3.0.0 生成，取值方式照 MD3 的 AnalyzeByJSonPath，见 tool/jsoup_oracle/
void main() {
  final fixture = jsonDecode(File('test/fixtures/json_path_cases.json').readAsStringSync()) as Map<String, Object?>;
  for (final raw in fixture['cases'] as List<Object?>) {
    final c = raw as Map<String, Object?>;
    test('${c['note']}：${c['path']}', () {
      final document = jsonDecode(c['doc'] as String);
      final path = JsonPath.parse(c['path'] as String);
      expect(path.isDefinite, c['definite']);

      // getString：列表按项连接，单值转字符串；出错或 null 值（Java 里 NPE）时为空串
      String string;
      try {
        final value = path.read(document);
        string = value is List ? value.map(jaywayString).join('\n') : (value == null ? '' : jaywayString(value));
      } on JsonPathNotFound {
        string = '';
      }
      expect(string, c['string']);

      // getStringList：遇到 null 项时 Java 抛 NPE，已经加入的项保留
      final list = <String>[];
      try {
        final value = path.read(document);
        for (final item in value is List ? value : [value]) {
          if (item == null) break;
          list.add(jaywayString(item));
        }
      } on JsonPathNotFound {
        // 同上
      }
      expect(list, c['list']);
    });
  }

  test('不支持的写法报错', () {
    expect(() => JsonPath.parse(r'$.list.length()'), throwsFormatException);
    expect(() => JsonPath.parse(r'$.list[?(@.a =~ /x/)]'), throwsFormatException);
    expect(() => JsonPath.parse(r'$.a.'), throwsFormatException);
  });

  test('Java 的 Double.toString', () {
    expect(javaDoubleString(1e20), '1.0E20');
    expect(javaDoubleString(1.5e-5), '1.5E-5');
    expect(javaDoubleString(1234567.0), '1234567.0');
    expect(javaDoubleString(12345678.9), '1.23456789E7');
    expect(javaDoubleString(0.001), '0.001');
    expect(javaDoubleString(-2.5), '-2.5');
  });
}
