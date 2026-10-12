import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:rule_engine/src/html/css_selector.dart';
import 'package:rule_engine/src/html/xpath.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 期望值由 JsoupXpath 2.5.5 按 MD3 的 AnalyzeByXPath 取值方式生成，见 tool/jsoup_oracle/
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  final fixture = jsonDecode(File('test/fixtures/xpath_cases.json').readAsStringSync()) as Map<String, Object?>;

  // 书源里 64 条不重复的 A 类 XPath（共 126 处）逐条和 JsoupXpath 对照，没有一条报错
  test('书源里的 XPath 报错条数', () {
    final real = [
      for (final c in (fixture['cases'] as List).cast<Map<String, Object?>>())
        if ((c['note'] as String).startsWith('书源：')) c,
    ];
    final errors = [for (final c in real) if (c['error'] == true) c['xpath']];
    printOnFailure('报错：$errors');
    expect(real, hasLength(64));
    expect(errors, isEmpty);
  });
  for (final raw in fixture['cases'] as List<Object?>) {
    final c = raw as Map<String, Object?>;
    test('${c['note']}：${c['xpath']}', () {
      List<String> run() {
        final ctx = c['ctx'] as String;
        var html = c['html'] as String;
        final List<Element> context;
        if (ctx.isEmpty) {
          // MD3 的 strToJXDocument：片段以 </td>、</tr> 结尾时补上外层
          if (html.endsWith('</td>')) html = '<tr>$html</tr>';
          if (html.endsWith('</tr>') || html.endsWith('</tbody>')) html = '<table>$html</table>';
          context = html_parser.parse(html).children;
        } else {
          context = [CssSelector.parse(ctx).select(env, html_parser.parse(html)).first as Element];
        }
        return XPath.parse(c['xpath'] as String).select(env, context).map(xpathNodeString).toList();
      }

      if (c['error'] == true) {
        expect(run, throwsFormatException);
      } else if ((c['xpath'] as String).contains('..') || (c['xpath'] as String).contains('descendant')) {
        // JsoupXpath 在 .. 和 descendant 轴上用 HashSet 去重，顺序取决于对象哈希，只比较内容
        expect(run(), unorderedEquals(c['items'] as List<Object?>));
      } else {
        expect(run(), c['items']);
      }
    });
  }
}
