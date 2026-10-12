import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:rule_engine/src/html/jsoup_text.dart';
import 'package:test/test.dart';

// 期望值由 jsoup 1.16.2 生成，见 tool/jsoup_oracle/
void main() {
  final fixture = jsonDecode(File('test/fixtures/jsoup_text_cases.json').readAsStringSync()) as Map<String, Object?>;
  for (final raw in fixture['cases'] as List<Object?>) {
    final c = raw as Map<String, Object?>;
    test('${c['note']}（${c['op']}）', () {
      final document = html_parser.parse(c['html'] as String);
      final elements = document.querySelectorAll(c['arg'] as String);
      final List<String> actual = switch (c['op']) {
        'text' => [for (final e in elements) jsoupText(e)],
        'ownText' => [for (final e in elements) jsoupOwnText(e)],
        'textNodes' => [for (final e in elements) jsoupTextNodes(e).join('\u0002')],
        'outerHtml' => [jsoupOuterHtmlAll(elements)],
        'data' => [for (final e in elements) jsoupData(e)],
        final op => throw ArgumentError(op),
      };
      expect(actual, c['items']);
    });
  }
}
