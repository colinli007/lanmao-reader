import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/source_list_page.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Map<String, Object?> source(String url, {String? name, Object? enabled, int? type, String? group}) => {
    'bookSourceUrl': url,
    'bookSourceName': name ?? url,
    'enabled': ?enabled,
    'bookSourceType': ?type,
    'bookSourceGroup': ?group,
  };

  List<String?> titles(WidgetTester tester) => tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();

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

  testWidgets('按分组筛选：一个书源可以属于多个分组，没分组的归到「未分组」', (tester) async {
    await services.addSources([
      source('https://a.com', name: '书源甲', group: '文学, 常用'),
      source('https://b.com', name: '书源乙', group: '常用；'),
      source('https://c.com', name: '书源丙'),
    ]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    await tester.tap(find.widgetWithText(ChoiceChip, '常用'));
    await tester.pump();
    expect(titles(tester), ['书源甲', '书源乙']);
    await tester.tap(find.widgetWithText(ChoiceChip, '未分组'));
    await tester.pump();
    expect(titles(tester), ['书源丙']);
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pump();
    expect(titles(tester), ['书源甲', '书源乙', '书源丙']);
  });

  testWidgets('子串筛选和分组筛选同时生效', (tester) async {
    await services.addSources([
      source('https://a.com', name: '笔趣阁', group: '常用'),
      source('https://b.com', name: '起点', group: '常用'),
      source('https://c.com', name: '笔趣阁二', group: '备用'),
    ]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    await tester.tap(find.widgetWithText(ChoiceChip, '常用'));
    await tester.enterText(find.byType(TextField), '笔趣');
    await tester.pump();
    expect(titles(tester), ['笔趣阁']);
  });

  testWidgets('没有任何分组时不显示分组筛选', (tester) async {
    await services.addSources([source('https://a.com'), source('https://b.com')]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('上方显示已启用数和总数', (tester) async {
    await services.addSources([
      for (var i = 0; i < 10; i++) source('https://$i.com', enabled: i < 7),
    ]);
    await tester.pumpWidget(services.app(const SourceListPage()));
    expect(find.text('已启用 7 / 共 10'), findsOneWidget);
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

  testWidgets(
    '从文件导入：Android 按 MIME 过滤（含识别不出类型的文件），其它平台按扩展名和 UTI；文件按 UTF-8 解码后进入预览',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      final picker = FileSelectorPlatform.instance = _FakeFileSelector(
        XFile.fromData(utf8.encode('{"bookSourceUrl":"https://a.com","bookSourceName":"书源甲"}'), name: 'a.json'),
      );
      addTearDown(() => FileSelectorPlatform.instance = original);
      await tester.pumpWidget(services.app(const SourceListPage()));
      await tester.tap(find.byTooltip('导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从文件导入'));
      await tester.pumpAndSettle();

      final group = picker.typeGroups!.single;
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(group.mimeTypes, ['application/json', 'text/plain', 'application/octet-stream']);
        expect(group.extensions, isNull);
      } else {
        // macOS 会把 MIME 换成 UTType，octet-stream 会放开所有文件
        expect(group.mimeTypes, isNull);
        expect(group.extensions, ['json', 'txt']);
        expect(group.uniformTypeIdentifiers, ['public.json', 'public.plain-text']);
      }
      expect(find.text('新增 1 个，更新 0 个，跳过 0 个'), findsOneWidget);
      await tester.tap(find.text('导入').last);
      await tester.pumpAndSettle();
      // 按 UTF-8 解码：Android 上的 XFile 是内存字节，它自己的 readAsString 会把中文解成乱码
      expect(find.text('书源甲'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.iOS}),
  );
}

class _FakeFileSelector extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.file);

  final XFile file;
  List<XTypeGroup>? typeGroups;

  @override
  Future<XFile?> openFile({List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async {
    typeGroups = acceptedTypeGroups;
    return file;
  }
}
