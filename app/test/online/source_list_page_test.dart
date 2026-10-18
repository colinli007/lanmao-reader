import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/source_list_page.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Map<String, Object?> source(String url, {String? name, Object? enabled, int? type}) => {
    'bookSourceUrl': url,
    'bookSourceName': name ?? url,
    'enabled': ?enabled,
    'bookSourceType': ?type,
  };

  Future<void> pasteImport(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文本导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  testWidgets('预览新增、更新和跳过，确认后写入', (tester) async {
    await services.addSources([source('https://a.com', name: '旧名字')]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    await pasteImport(
      tester,
      '[{"bookSourceUrl":"https://a.com","bookSourceName":"新名字"},{"bookSourceUrl":"https://b.com","bookSourceName":"B"},{"bookSourceName":"没有地址"}]',
    );
    expect(find.text('新增 1 个，更新 1 个，跳过 1 个'), findsOneWidget);
    expect(find.text('第 3 项：缺少书源地址'), findsOneWidget);
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect([for (final e in services.repository.entries) (e.url, e.source.bookSourceName)], [
      ('https://a.com', '新名字'),
      ('https://b.com', 'B'),
    ]);
    expect(find.text('新名字'), findsOneWidget);
  });

  testWidgets('取消预览不做任何改动', (tester) async {
    await tester.pumpWidget(services.app(const SourceListPage()));
    await pasteImport(tester, '{"bookSourceUrl":"https://a.com"}');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(services.repository.entries, isEmpty);
  });

  testWidgets('不是书源 JSON 时显示原因，书源列表不变', (tester) async {
    await tester.pumpWidget(services.app(const SourceListPage()));
    await pasteImport(tester, 'hello');
    expect(find.text('无法导入'), findsOneWidget);
    expect(find.textContaining('不是书源 JSON'), findsOneWidget);
    expect(services.repository.entries, isEmpty);
  });

  testWidgets('导入时 enabled 为 false 的书源处于停用状态', (tester) async {
    await tester.pumpWidget(services.app(const SourceListPage()));
    await pasteImport(tester, '{"bookSourceUrl":"https://a.com","enabled":false}');
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(services.repository['https://a.com']!.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('列表按首次导入顺序，标出非文本类型，按名字或地址筛选', (tester) async {
    await services.addSources([source('https://x.com', name: '笔趣阁'), source('https://y.com', name: '起点', type: 2)]);
    await services.addSources([source('https://x.com', name: '笔趣阁')]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
    expect(titles, ['笔趣阁', '起点']);
    expect(find.text('图片 · https://y.com'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '笔趣');
    await tester.pump();
    expect(find.text('起点'), findsNothing);
    await tester.enterText(find.byType(TextField), 'y.com');
    await tester.pump();
    expect(find.text('笔趣阁'), findsNothing);
    expect(find.text('起点'), findsOneWidget);
  });

  testWidgets('单个开关和多选批量启用、停用、删除（删除前确认）', (tester) async {
    await services.addSources([source('https://a.com'), source('https://b.com'), source('https://c.com')]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(services.repository['https://a.com']!.enabled, isFalse);

    await tester.longPress(find.text('https://b.com').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://c.com').first);
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个'), findsOneWidget);
    await tester.tap(find.byTooltip('停用'));
    await tester.pumpAndSettle();
    expect([for (final e in services.repository.entries) e.enabled], [false, false, false]);
    await tester.tap(find.byTooltip('启用'));
    await tester.pumpAndSettle();
    expect([for (final e in services.repository.entries) e.enabled], [false, true, true]);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 个书源？'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect([for (final e in services.repository.entries) e.url], ['https://a.com']);
  });

  testWidgets('导出：原始内容，enabled 是当前状态；没选中时导出全部', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    await services.addSources([
      {...source('https://a.com'), 'ruleSearch': {'name': 'h1'}, 'enabled': true},
      source('https://b.com'),
    ]);
    await services.repository.setEnabled({'https://a.com'}, false);
    await tester.pumpWidget(services.app(const SourceListPage()));
    await tester.tap(find.byTooltip('导出全部'));
    await tester.pumpAndSettle();
    expect(find.text('已复制 2 个书源到剪贴板'), findsOneWidget);
    expect(clipboard, contains('"enabled": false'));
    expect(clipboard, contains('"ruleSearch": {\n      "name": "h1"\n    }'));
  });
}
