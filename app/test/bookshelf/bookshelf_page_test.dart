import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/bookshelf/bookshelf_page.dart';
import 'package:novel_reader/library/book_cover.dart';
import 'package:novel_reader/online/book_detail_page.dart';
import 'package:novel_reader/online/search_page.dart';
import 'package:novel_reader/reader/reader_page.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 100);
  });
  tearDown(() => services.db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const BookshelfPage()));
    await tester.pumpAndSettle();
  }

  void tocOf(int count) => services.engine.onChapterList = (source, book) async => (
    book: book,
    chapters: [
      for (var i = 0; i < count; i++)
        BookChapter(bookUrl: book.bookUrl, baseUrl: '${SimpleBook.bookUrl}/toc')
          ..index = i
          ..title = '第$i章'
          ..url = '/$i.html',
    ],
  );

  /// 下拉书架，开始更新目录。
  Future<void> pullToRefresh(WidgetTester tester) async {
    await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> longPressAndChoose(WidgetTester tester, String action) async {
    await tester.longPress(find.text('三体').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  Future<String?> latestChapter() async => (await services.db.getBook(SimpleBook.bookUrl))!.latestChapterTitle;

  testWidgets('空书架提示去搜索，点了进入搜索页', (tester) async {
    await pump(tester);
    expect(find.text('书架还是空的'), findsOneWidget);
    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
  });

  testWidgets('显示书名和未读章节数，不显示作者和最新章节', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 89, url: '/89.html', title: '第89章', position: 0, now: DateTime(2026));
    await pump(tester);
    expect(find.text('三体'), findsNWidgets(2));
    expect(find.text('10 章未读'), findsOneWidget);
    expect(find.textContaining('刘慈欣'), findsNothing);
  });

  testWidgets('读到最新一章时只有书名，没有状态', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 99, url: '/99.html', title: '第99章', position: 0, now: DateTime(2026));
    await pump(tester);
    expect(find.text('三体'), findsNWidgets(2));
    expect(find.textContaining('章未读'), findsNothing);
  });

  testWidgets('没有封面时占位封面上写书名', (tester) async {
    await services.shelveSimpleBook();
    await pump(tester);
    // 测试里的书都没有封面：一个在占位封面上，一个在封面下面
    expect(find.text('三体'), findsNWidgets(2));
  });

  testWidgets('手机竖屏（390 宽）每行三本，宽窗口（1000 宽）每行更多，封面宽度大致不变', (tester) async {
    for (var i = 0; i < 10; i++) {
      await services.shelveSimpleBook(url: '${SimpleBook.bookUrl}/$i', name: '书$i');
    }
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    (int, double) columns() {
      final delegate = tester.widget<GridView>(find.byType(GridView)).gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return (delegate.crossAxisCount, tester.getSize(find.byType(BookCover).first).width);
    }

    tester.view.physicalSize = const Size(390, 844);
    await pump(tester);
    final (phone, phoneCover) = columns();
    expect(phone, 3);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    final (wide, wideCover) = columns();
    expect(wide, greaterThan(3));
    expect(wideCover, closeTo(phoneCover, 30));
  });

  testWidgets('点击直接打开阅读页，从保存的进度继续', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.tap(find.text('三体').first);
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect((reader.bookUrl, reader.startAt), (SimpleBook.bookUrl, null));
  });

  testWidgets('长按选详情，打开详情页', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await longPressAndChoose(tester, '详情');
    expect(find.byType(BookDetailPage), findsOneWidget);
  });

  testWidgets('长按选移出书架，确认后移出', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await longPressAndChoose(tester, '移出书架');
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(find.text('三体'), findsNothing);
    expect(await services.db.getBook(SimpleBook.bookUrl), isNull);
  });

  testWidgets('下拉刷新发现新章节：最新章节更新，未读章节数为 2', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 99, url: '/99.html', title: '第99章', position: 0, now: DateTime(2026));
    tocOf(102);
    await pump(tester);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(services.engine.calls, ['toc ${SimpleBook.bookUrl}']);
    expect(find.text('2 章未读'), findsOneWidget);
    expect(await latestChapter(), '第101章');
    expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterIndex, 99);
  });

  testWidgets('更新失败保留原目录，书上有失败标记，长按能看到失败原因', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    services.engine.onChapterList = (source, book) => Future.error(const HostCallException('连接超时'));
    await pump(tester);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('更新失败'), findsOneWidget);
    await longPressAndChoose(tester, '失败原因');
    expect(find.text('网络错误：连接超时'), findsOneWidget);
    expect(await services.db.chaptersOf(SimpleBook.bookUrl), hasLength(100));
    expect(await latestChapter(), '第99章');
  });

  testWidgets('没有失败时长按没有「失败原因」', (tester) async {
    await services.shelveSimpleBook();
    await pump(tester);
    await tester.longPress(find.text('三体').first);
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('失败原因'), findsNothing);
  });

  testWidgets('长按换书源：成功后回到书架，提示新书源，原来的失败标记不再显示', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    services.engine.onChapterList = (source, book) => Future.error(const HostCallException('连接超时'));
    await pump(tester);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('更新失败'), findsOneWidget);

    await services.addSources([{'bookSourceUrl': 'https://b.com', 'bookSourceName': '书源乙', 'searchUrl': '/s'}]);
    services.engine
      ..onSearch = ((source, key) async => [
        SearchBook(bookUrl: '${source.bookSourceUrl}/book/1', origin: source.bookSourceUrl, originName: source.bookSourceName)
          ..name = '三体'
          ..author = '刘慈欣',
      ])
      ..onBookInfo = ((source, book) async => book);
    tocOf(3);
    await longPressAndChoose(tester, '换书源');
    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();

    expect(find.byType(BookshelfPage), findsOneWidget);
    expect(find.text('已换到书源乙'), findsOneWidget);
    expect(find.text('更新失败'), findsNothing);
    expect((await services.db.getBook('https://b.com/book/1'))!.latestChapterTitle, '第2章');
    // 换过去以后点这本书，打开新书源的阅读页
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('三体').first);
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).bookUrl, 'https://b.com/book/1');
  });

  testWidgets('书源已删除：不请求网络，标出书源不存在；书架上的书保留', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.repository.delete({SimpleBook.sourceUrl});
    await pump(tester);
    expect(find.text('三体'), findsNWidgets(2));
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(services.engine.calls, isEmpty);
    expect(find.text('书源不存在'), findsOneWidget);
  });

  testWidgets('更新中显示进度，停止后原目录不变', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    final pending = Completer<TocResult>();
    services.engine.onChapterList = (source, book) => pending.future;
    await pump(tester);
    await pullToRefresh(tester);
    expect(find.text('正在更新目录 0/1'), findsOneWidget);
    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    expect(services.engine.batches.single.isStopped, isTrue);
    expect(find.text('正在更新目录 0/1'), findsNothing);
    tocOf(102);
    pending.complete(await services.engine.onChapterList!(services.repository[SimpleBook.sourceUrl]!.source, Book(bookUrl: SimpleBook.bookUrl, origin: '', originName: '')));
    await tester.pumpAndSettle();
    expect(await services.db.chaptersOf(SimpleBook.bookUrl), hasLength(100));
  });

  testWidgets('macOS 上有「更新目录」按钮，效果和下拉刷新相同', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await services.shelveSimpleBook(chapters: 100);
    tocOf(102);
    await pump(tester);
    await tester.tap(find.byTooltip('更新目录'));
    await tester.pumpAndSettle();
    expect(services.engine.calls, ['toc ${SimpleBook.bookUrl}']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('手机上没有「更新目录」按钮', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await services.shelveSimpleBook();
    await pump(tester);
    expect(find.byTooltip('更新目录'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
