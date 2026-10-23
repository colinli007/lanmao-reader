import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/settings/byte_size.dart';
import 'package:novel_reader/settings/settings_page.dart';
import 'package:novel_reader/storage/database.dart';

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
    expect(find.text('关于'), findsOneWidget);
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
}
