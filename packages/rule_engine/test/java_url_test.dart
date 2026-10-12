import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/net/java_url.dart';
import 'package:test/test.dart';

// 期望值由 java.net.URL 按 MD3 的 NetworkUtils.getAbsoluteURL 生成，见 tool/jsoup_oracle/
void main() {
  final fixture = jsonDecode(File('test/fixtures/url_cases.json').readAsStringSync()) as Map<String, Object?>;
  for (final raw in fixture['cases'] as List<Object?>) {
    final c = raw as Map<String, Object?>;
    test('${c['note']}：${c['relative']}', () {
      expect(absoluteUrlFrom(c['base'] as String, c['relative'] as String), c['expected']);
    });
  }
}
