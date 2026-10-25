import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/replace_rule_list_page.dart';

import '../support/test_app.dart';

/// replace-rules「新建和编辑规则」：从列表页进入编辑页。
void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const ReplaceRuleListPage()));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('新建规则：排在最后，已启用', (tester) async {
    await services.addReplaceRules([{'id': 1, 'name': '已有', 'pattern': 'a', 'order': 3}]);
    await pump(tester);
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(field('替换规则'), '最新章节请到.*?阅读');
    await save(tester);

    expect(find.text('新建替换规则'), findsNothing);
    final created = services.replaceRules.entries.last;
    expect((created.rule.pattern, created.rule.isRegex, created.enabled, created.rule.order), ('最新章节请到.*?阅读', true, true, 4));
    expect(find.text('最新章节请到.*?阅读'), findsOneWidget);
  });

  testWidgets('正则写错或替换规则为空时不保存，显示原因', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('替换规则为空'), findsOneWidget);

    await tester.enterText(field('替换规则'), '(未闭合');
    await save(tester);
    expect(find.text('正则无法编译'), findsOneWidget);
    expect(services.replaceRules.entries, isEmpty);

    // 不当正则时可以保存
    await tester.tap(find.text('使用正则'));
    await save(tester);
    expect(services.replaceRules.entries.single.rule.isRegex, isFalse);
  });

  testWidgets('编辑：表单里的字段更新，分组、超时时间和启用状态不变', (tester) async {
    await services.addReplaceRules([
      {'id': 1, 'name': '旧', 'pattern': 'a', 'group': '广告', 'timeoutMillisecond': 500, 'isEnabled': false},
    ]);
    await pump(tester);
    await tester.tap(find.text('旧'));
    await tester.pumpAndSettle();
    expect(find.text('编辑替换规则'), findsOneWidget);
    await tester.enterText(field('名称'), '新');
    await tester.enterText(field('作用范围'), '三体');
    await tester.tap(find.text('作用于章节名'));
    await save(tester);

    final edited = services.replaceRules.entries.single;
    expect((edited.rule.name, edited.rule.scope, edited.rule.scopeTitle, edited.rule.pattern), ('新', '三体', true, 'a'));
    expect((edited.rule.json['group'], edited.rule.timeout, edited.enabled), ('广告', const Duration(milliseconds: 500), false));
  });

  testWidgets('删除前确认', (tester) async {
    await services.addReplaceRules([{'id': 1, 'name': '去广告', 'pattern': 'a'}]);
    await pump(tester);
    await tester.tap(find.text('去广告'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(services.replaceRules.entries, hasLength(1));

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(services.replaceRules.entries, isEmpty);
    expect(find.text('还没有替换规则，点右上角导入或新建'), findsOneWidget);
  });
}
