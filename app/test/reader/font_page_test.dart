import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/font_page.dart';
import 'package:lanmao_reader/reader/reader_fonts.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/ui/theme.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  late Directory directory;
  late ReaderFonts fonts;
  late Uint8List validFont;
  late FileSelectorPlatform originalPicker;

  setUp(() async {
    services = await TestServices.create();
    directory = await Directory.systemTemp.createTemp('font-page-test-');
    fonts = ReaderFonts(directory: directory);
    validFont = await File('assets/fonts/lucide.ttf').readAsBytes();
    originalPicker = FileSelectorPlatform.instance;
  });

  tearDown(() async {
    FileSelectorPlatform.instance = originalPicker;
    await services.db.close();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {String selected = ''}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...services.overrides,
          readerFontsProvider.overrideWith((ref) => fonts),
          initialSettingsProvider.overrideWithValue(
            ReaderSettings(fontId: selected).toMap(),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const FontPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReaderSettings settings(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(FontPage)),
  ).read(readerSettingsProvider);

  ListTile tile(WidgetTester tester, String name) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, name));

  testWidgets('选择已导入字体和切回系统字体都更新预览并落盘', (tester) async {
    final imported = (await tester.runAsync(
      () => fonts.import('自定义字体.ttf', validFont),
    ))!;
    await open(tester);
    expect(tile(tester, '系统字体').selected, isTrue);
    await tester.tap(find.text('自定义字体'));
    await tester.pumpAndSettle();
    expect(tile(tester, '自定义字体').selected, isTrue);
    expect(tile(tester, '系统字体').selected, isFalse);
    expect(settings(tester).fontId, imported.id);
    expect(
      ReaderSettings.fromMap(
        (await tester.runAsync(() => services.db.loadSettings()))!,
      ).fontId,
      imported.id,
    );
    final preview = tester.widget<Text>(find.text('山色有无中，江流天地外。\n阅读，让故事慢慢展开。'));
    expect(preview.style?.fontFamily, imported.family);

    await tester.tap(find.text('系统字体'));
    await tester.pumpAndSettle();
    expect(tile(tester, '系统字体').selected, isTrue);
    expect(settings(tester).fontId, '');
    expect(
      ReaderSettings.fromMap(
        (await tester.runAsync(() => services.db.loadSettings()))!,
      ).fontId,
      '',
    );
  });

  testWidgets('删除正在使用的字体需确认，确认后移除副本并持久化系统字体', (tester) async {
    final imported = (await tester.runAsync(
      () => fonts.import('使用中的字体.ttf', validFont),
    ))!;
    await open(tester, selected: imported.id);
    final dynamic removeAction = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '删除字体 使用中的字体',
          ),
        )
        .onPressed;
    late Future<void> removal;
    await tester.runAsync(() async {
      removal = removeAction();
    });
    await tester.pumpAndSettle();
    expect(find.text('删除字体？'), findsOneWidget);
    expect(fonts.entries, hasLength(1));
    expect(settings(tester).fontId, imported.id);

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.runAsync(() => removal);
    await tester.pumpAndSettle();
    expect(find.text('使用中的字体'), findsNothing);
    expect(tile(tester, '系统字体').selected, isTrue);
    expect(settings(tester).fontId, '');
    expect(
      ReaderSettings.fromMap(
        (await tester.runAsync(() => services.db.loadSettings()))!,
      ).fontId,
      '',
    );
    expect(await tester.runAsync(() => imported.file.parent.exists()), isFalse);
  });

  testWidgets('文件选择取消保留当前字体，也不新增文件', (tester) async {
    final imported = (await tester.runAsync(
      () => fonts.import('当前字体.ttf', validFont),
    ))!;
    FileSelectorPlatform.instance = _FakeFileSelector(null);
    await open(tester, selected: imported.id);
    await tester.tap(find.text('导入字体'));
    await tester.pumpAndSettle();
    expect(settings(tester).fontId, imported.id);
    expect(tile(tester, '当前字体').selected, isTrue);
    expect(fonts.entries, hasLength(1));
    expect(find.text('无法使用字体'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('非法字体显示错误，关闭提示后原字体仍选中且可操作', (tester) async {
    final imported = (await tester.runAsync(
      () => fonts.import('当前字体.ttf', validFont),
    ))!;
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(Uint8List.fromList([0, 1, 2]), path: '坏字体.ttf'),
    );
    await open(tester, selected: imported.id);
    await tester.tap(find.text('导入字体'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 完成弹窗过渡，后台进度条仍在转。
    expect(find.text('无法使用字体'), findsOneWidget);
    expect(find.textContaining('字体文件无效或已损坏'), findsOneWidget);
    expect(settings(tester).fontId, imported.id);
    expect(fonts.entries, hasLength(1));
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('无法使用字体'), findsNothing);
    expect(tile(tester, '当前字体').selected, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('系统字体'));
    await tester.pumpAndSettle();
    expect(settings(tester).fontId, '');
  });

  testWidgets(
    '文件选择成功导入并选中：三端过滤条件符合平台，文件存入应用目录',
    (tester) async {
      final picker = _FakeFileSelector(
        XFile.fromData(validFont, path: '新字体.ttf'),
      );
      FileSelectorPlatform.instance = picker;
      await open(tester);
      // 按钮回调返回整个导入任务；在真实异步区等待它，避免用固定延迟猜测文件写入何时结束。
      final dynamic importAction = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '导入字体'))
          .onPressed;
      await tester.runAsync(() async => await importAction());
      await tester.pumpAndSettle();
      final imported = fonts.entries.single;
      expect(find.text('新字体'), findsOneWidget);
      expect(tile(tester, '新字体').selected, isTrue);
      expect(settings(tester).fontId, imported.id);
      expect(
        ReaderSettings.fromMap(
          (await tester.runAsync(() => services.db.loadSettings()))!,
        ).fontId,
        imported.id,
      );
      expect(
        await tester.runAsync(() => imported.file.readAsBytes()),
        orderedEquals(validFont),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final group = picker.typeGroups!.single;
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(
          group.mimeTypes,
          containsAll(['font/ttf', 'font/otf', 'application/octet-stream']),
        );
        expect(group.extensions, isNull);
      } else {
        expect(group.extensions, ['ttf', 'otf']);
        expect(group.uniformTypeIdentifiers, [
          'public.truetype-ttf-font',
          'public.opentype-font',
        ]);
        expect(group.mimeTypes, isNull);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );
}

class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.file);

  final XFile? file;
  List<XTypeGroup>? typeGroups;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    typeGroups = acceptedTypeGroups;
    return file;
  }
}
