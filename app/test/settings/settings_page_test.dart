import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/source_list_page.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/settings/byte_size.dart';
import 'package:lanmao_reader/settings/settings_page.dart';
import 'package:lanmao_reader/storage/database.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Future<int> cache(String bookUrl, int chapters) async {
    var bytes = 0;
    for (var i = 0; i < chapters; i++) {
      final content = '$bookUrl 第$i章正文';
      bytes += utf8.encode(content).length;
      await services.db.putContent(ContentRow(bookUrl: bookUrl, chapterUrl: '/$i', title: '第$i章', content: content));
    }
    return bytes;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const SettingsPage()));
    await tester.pumpAndSettle();
  }

  Finder clearButton() => find.widgetWithText(TextButton, '清除');

  testWidgets('显示所有书的已缓存章节数和大小', (tester) async {
    final bytes = await cache('a', 3) + await cache('b', 2);
    await pump(tester);
    expect(find.text('5 章 · ${formatByteSize(bytes)}'), findsOneWidget);
    for (final item in ['书源', '替换净化规则', '阅读设置', '关于']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  });

  testWidgets('没有缓存时显示 0 章，不能清除', (tester) async {
    await pump(tester);
    expect(find.text('0 章 · 0 B'), findsOneWidget);
    expect(tester.widget<TextButton>(clearButton()).onPressed, isNull);
  });

  testWidgets('确认后清除，显示 0 章', (tester) async {
    await cache('a', 5);
    await pump(tester);
    await tester.tap(clearButton());
    await tester.pumpAndSettle();
    expect(find.textContaining('会删除已缓存的 5 章正文'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();
    expect(find.text('0 章 · 0 B'), findsOneWidget);
    expect(await services.db.contentCacheStats(), (chapters: 0, bytes: 0));
  });

  testWidgets('确认时取消，不删除', (tester) async {
    final bytes = await cache('a', 5);
    await pump(tester);
    await tester.tap(clearButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('5 章 · ${formatByteSize(bytes)}'), findsOneWidget);
    expect(await services.db.getContent('a', '/0'), isNotNull);
  });

  testWidgets('点关于进入关于页', (tester) async {
    await pump(tester);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('免责声明'), findsOneWidget);
  });

  testWidgets('点替换净化规则进入规则列表', (tester) async {
    await pump(tester);
    await tester.tap(find.text('替换净化规则'));
    await tester.pumpAndSettle();
    expect(find.text('还没有替换规则，点右上角导入或新建'), findsOneWidget);
  });

  testWidgets('点书源进入书源列表', (tester) async {
    await pump(tester);
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceListPage), findsOneWidget);
  });

  group('阅读设置页', () {
    /// 进入阅读设置页，点 [toggle] 那个开关，再打开一本书的阅读页。
    Future<void> toggleThenRead(WidgetTester tester, String toggle) async {
      await services.useSimpleBook();
      await services.shelveSimpleBook();
      await pump(tester);
      await tester.tap(find.text('阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(toggle));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text(toggle))).push(
        MaterialPageRoute<void>(builder: (_) => const ReaderPage(bookUrl: SimpleBook.bookUrl, startAt: 0)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('关掉跟随系统深色：系统是深色时阅读页用选的亮主题，并落盘', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await toggleThenRead(tester, '跟随系统深色');
      final scaffold = tester.widget<Scaffold>(find.descendant(of: find.byType(ReaderPage), matching: find.byType(Scaffold)).first);
      expect(scaffold.backgroundColor, ReaderTheme.light.background);
      expect((await services.db.loadSettings())['reader.followSystemDark'], 'false');
    });

    testWidgets('打开屏幕常亮：进入阅读页时常亮，并落盘', (tester) async {
      await toggleThenRead(tester, '屏幕常亮');
      expect(services.screen.calls, [true]);
      expect((await services.db.loadSettings())['reader.keepScreenOn'], 'true');
    });
  });
}
