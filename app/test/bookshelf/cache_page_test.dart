import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/bookshelf/cache_page.dart';

import '../support/test_app.dart';

// book-cache「缓存管理页」
void main() {
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 20, paragraphs: 2);
  });
  tearDown(() => services.db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const CachePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('书架是空的时提示', (tester) async {
    await pump(tester);
    expect(find.text('书架是空的'), findsOneWidget);
  });

  testWidgets('从这里发起缓存，看进度和失败数，停止后不再请求新的章节', (tester) async {
    await services.shelveSimpleBook(chapters: 20);
    final release = Completer<void>();
    final original = services.engine.onContent!;
    services.engine.onContent = (source, book, chapter, next) async {
      if (chapter.title == '第0章') throw Exception('404');
      if (chapter.index >= 5) await release.future;
      return original(source, book, chapter, next);
    };
    await pump(tester);
    expect(find.text('已缓存 0 / 20 章'), findsOneWidget);
    await tester.tap(find.text('缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部章节（20 章）'));
    await tester.pumpAndSettle();
    expect(find.text('已缓存 4 / 20 章 · 缓存中 5 / 20 · 失败 1 章'), findsOneWidget);
    final requested = services.engine.calls.length;
    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    expect(find.text('已缓存 4 / 20 章 · 上次失败 1 章'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    release.complete();
    await tester.pumpAndSettle();
    expect(services.engine.calls.length, requested, reason: '停止后排队的章节不再请求');
  });
}
