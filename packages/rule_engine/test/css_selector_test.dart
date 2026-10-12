import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:rule_engine/src/html/css_selector.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 期望值由 jsoup 1.16.2 生成，见 tool/jsoup_oracle/
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  final fixture = jsonDecode(File('test/fixtures/jsoup_selector_cases.json').readAsStringSync()) as Map<String, Object?>;
  for (final raw in fixture['cases'] as List<Object?>) {
    final c = raw as Map<String, Object?>;
    test('${c['note']}：${c['arg']}', () {
      final document = html_parser.parse(c['html'] as String);
      // jsoup 的 getAllElements：从根开始的先序遍历，根是第 0 个
      final all = <Node>[document];
      void walk(Node node) {
        for (final child in node.nodes) {
          if (child is Element) {
            all.add(child);
            walk(child);
          }
        }
      }

      walk(document);
      String index(Node node) => '${all.indexOf(node)}';

      List<String> run() {
        final ctx = c['ctx'] as String;
        final Node root = ctx.isEmpty ? document : CssSelector.parse(ctx).select(env, document).first;
        final arg = c['arg'] as String;
        return switch (c['op']) {
          'select' => CssSelector.parse(arg).select(env, root).map(index).toList(),
          'byClass' => collectByClass(env, root, arg).map(index).toList(),
          'byTag' => collectByTag(env, root, arg).map(index).toList(),
          'byId' => collectById(env, root, arg).map(index).toList(),
          'ownTextContains' => collectContainingOwnText(env, root, arg).map(index).toList(),
          'attr' => [for (final node in CssSelector.parse('*').select(env, root)) jsoupAttr(node, arg)],
          final op => throw ArgumentError(op),
        };
      }

      if (c.containsKey('error')) {
        expect(run, throwsFormatException);
      } else {
        expect(run(), c['items']);
      }
    });
  }
}
