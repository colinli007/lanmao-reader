import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/replace_rule_list_page.dart';

import '../support/test_app.dart';

/// replace-rules「导入替换规则」「规则列表」「导出替换规则」。
void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const ReplaceRuleListPage()));
    await tester.pumpAndSettle();
  }

  Future<void> pasteImport(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文本导入'));
    await tester.pumpAndSettle();
    expect(find.text('粘贴替换规则 JSON'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  testWidgets('没有规则时提示导入或新建', (tester) async {
    await pump(tester);
    expect(find.text('还没有替换规则，点右上角导入或新建'), findsOneWidget);
  });

  testWidgets('粘贴导入：预览新增、更新、跳过和原因，确认后写入；名称为空时显示替换规则', (tester) async {
    await services.addReplaceRules([{'id': 1, 'name': '旧名字', 'pattern': 'a'}]);
    await pump(tester);
    await pasteImport(tester, '[{"id": 1, "name": "去本站广告", "pattern": "请记住本站.*"}, {"id": 2, "pattern": "最新章节"}, {"pattern": "[未闭合"}]');
    expect(find.text('新增 1 条，更新 1 条，跳过 1 条'), findsOneWidget);
    expect(find.text('第 3 项：正则无法编译'), findsOneWidget);
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(find.text('去本站广告'), findsOneWidget);
    expect(find.text('最新章节'), findsOneWidget);
    expect(find.text('已导入 2 条替换规则'), findsOneWidget);
  });

  testWidgets('不是 JSON 时显示原因，不写入', (tester) async {
    await pump(tester);
    await pasteImport(tester, 'hello');
    expect(find.text('无法导入'), findsOneWidget);
    expect(find.textContaining('不是替换规则 JSON'), findsOneWidget);
    expect(services.replaceRules.entries, isEmpty);
  });

  testWidgets('关掉开关：立即停用并落盘', (tester) async {
    await services.addReplaceRules([{'id': 1, 'name': '去本站广告', 'pattern': 'a'}]);
    await pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(services.replaceRules.isEnabled(1), isFalse);
    expect((await services.db.allReplaceRules()).single.enabled, isFalse);
  });

  testWidgets('导出全部到剪贴板：isEnabled 是当前状态', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    await services.addReplaceRules([{'id': 1, 'pattern': 'a', 'group': '广告'}, {'id': 2, 'pattern': 'b'}]);
    await services.replaceRules.setEnabled(2, false);
    await pump(tester);
    await tester.tap(find.byTooltip('导出全部'));
    await tester.pumpAndSettle();
    final exported = jsonDecode(clipboard!) as List;
    expect([for (final rule in exported) ((rule as Map)['pattern'], rule['isEnabled'])], [('a', true), ('b', false)]);
    expect((exported.first as Map)['group'], '广告');
    expect(find.text('已复制 2 条替换规则到剪贴板'), findsOneWidget);
  });
}
