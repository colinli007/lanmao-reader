import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/app_shell.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:rule_engine/rule_engine.dart';

import 'support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 10);
  });
  tearDown(() => services.db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const AppShell()));
    await tester.pumpAndSettle();
  }

  double shelfOffset(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  testWidgets('切到设置再切回，书架的滚动位置不变', (tester) async {
    for (var i = 0; i < 30; i++) {
      await services.shelveSimpleBook(url: '${SimpleBook.bookUrl}/$i', name: '书$i');
    }
    await pump(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = shelfOffset(tester);
    expect(offset, greaterThan(0));

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('正文缓存'), findsOneWidget);
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    expect(shelfOffset(tester), offset);
  });

  testWidgets('切到书架再切回，发现 tab 展开的书源还在', (tester) async {
    await services.addSources([
      {'bookSourceUrl': 'https://e.com', 'bookSourceName': '发现源', 'exploreUrl': '玄幻::/xh'},
    ]);
    services.engine.onExploreKinds = (source) async => const [ExploreKind('玄幻', url: '/xh')];
    await pump(tester);
    await tester.tap(find.byTooltip('发现'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现源'));
    await tester.pumpAndSettle();
    expect(find.text('玄幻'), findsOneWidget);

    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    expect(find.text('玄幻'), findsNothing);
    await tester.tap(find.byTooltip('发现'));
    await tester.pumpAndSettle();
    expect(find.text('玄幻'), findsOneWidget);
  });

  testWidgets('打开阅读页时没有底部 tab，返回后回到书架', (tester) async {
    await services.shelveSimpleBook();
    await pump(tester);
    await tester.tap(find.text('三体').first);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('三体'), findsWidgets);
  });

  testWidgets('每次切到设置时重新统计正文缓存', (tester) async {
    Future<void> cache(String bookUrl, int chapters) async {
      for (var i = 0; i < chapters; i++) {
        await services.db.putContent(ContentRow(bookUrl: bookUrl, chapterUrl: '/$i', title: '第$i章', content: '正文'));
      }
    }

    await cache('a', 5);
    await pump(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 章'), findsOneWidget);

    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    await cache('b', 2);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('7 章'), findsOneWidget);
  });
}
