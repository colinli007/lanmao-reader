import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/bookshelf/bookshelf_page.dart';
import 'package:novel_reader/online/book_detail_page.dart';
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

  /// 手机宽度，高到大图、追更中和宫格都在屏幕上。
  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(services.app(const BookshelfPage()));
    await tester.pumpAndSettle();
  }

  /// 下拉刷新（手机上没有更新目录按钮，只在 macOS 上有）。
  Future<void> pullToRefresh(WidgetTester tester) => tester.fling(find.byType(RefreshIndicator), const Offset(0, 400), 1000);

  /// 宫格里的那本书（大图、没有封面时的占位上也有书名）。
  Finder gridBook() => find.text('三体').last;

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

  testWidgets('长按书打开菜单，进入详情', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.longPress(gridBook());
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
  });

  testWidgets('没做的功能点了提示暂未开发', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.tap(find.text('本地'));
    await tester.pump();
    expect(find.text('本地书暂未开发'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('macOS 顶栏有更新目录按钮，手机上只能下拉', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    final desktop = defaultTargetPlatform == TargetPlatform.macOS;
    expect(find.byTooltip('更新目录'), desktop ? findsOneWidget : findsNothing);
    if (!desktop) return;
    tocOf(102);
    await tester.tap(find.byTooltip('更新目录'));
    await tester.pumpAndSettle();
    expect(services.engine.calls, ['toc ${SimpleBook.bookUrl}']);
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS}));

  testWidgets('空书架提示去搜索', (tester) async {
    await pump(tester);
    expect(find.text('书架是空的，去搜索添加吧'), findsOneWidget);
  });

  testWidgets('最近读的书做大图：书名、作者、当前章节、进度和未读章节数；大图里的书不在追更中重复出现', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 89, url: '/89.html', title: '第89章', position: 0, now: DateTime.now());
    await pump(tester);
    expect(find.text('三体'), findsWidgets);
    expect(find.text('刘慈欣'), findsOneWidget);
    expect(find.text('第89章'), findsOneWidget);
    expect(find.text('90%  ·  余 10 章'), findsOneWidget);
    // 大图里的书不在追更中重复出现
    expect(find.text('追更中'), findsNothing);
  });

  testWidgets('读完筛选：只剩读到最后一章的书', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    expect(find.text('未开始'), findsOneWidget);
    await tester.tap(find.text('读完'));
    await tester.pumpAndSettle();
    expect(find.text('未开始'), findsNothing);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 99, url: '/99.html', title: '第99章', position: 0, now: DateTime.now());
    await tester.pumpAndSettle();
    expect(find.text('已读完'), findsOneWidget);
  });

  testWidgets('点击直接打开阅读页，从保存的进度继续', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.tap(gridBook());
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect((reader.bookUrl, reader.startAt, reader.introMenu), (SimpleBook.bookUrl, null, true));
    // 等菜单自动收起
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('确认后移出书架', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.longPress(gridBook());
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出书架'));
    await tester.pumpAndSettle();
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
    expect(find.text('98%  ·  余 2 章'), findsOneWidget);
    expect((await services.db.getBook(SimpleBook.bookUrl))!.latestChapterTitle, '第101章');
    expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterIndex, 99);
  });

  testWidgets('更新失败保留原目录，书上有失败标记', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    services.engine.onChapterList = (source, book) => Future.error(const HostCallException('连接超时'));
    await pump(tester);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    // 大图和宫格里各一个
    expect(find.text('更新失败'), findsNWidgets(2));
    await tester.tap(find.text('更新失败').first);
    await tester.pump();
    expect(find.text('网络错误：连接超时'), findsOneWidget);
    expect(await services.db.chaptersOf(SimpleBook.bookUrl), hasLength(100));
  });

  testWidgets('菜单里换书源：成功后回到书架，提示新书源，原来的失败标记不再显示', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    services.engine.onChapterList = (source, book) => Future.error(const HostCallException('连接超时'));
    await pump(tester);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('更新失败'), findsWidgets);

    await services.addSources([{'bookSourceUrl': 'https://b.com', 'bookSourceName': '书源乙', 'searchUrl': '/s'}]);
    services.engine
      ..onSearch = ((source, key) async => [
        SearchBook(bookUrl: '${source.bookSourceUrl}/book/1', origin: source.bookSourceUrl, originName: source.bookSourceName)
          ..name = '三体'
          ..author = '刘慈欣',
      ])
      ..onBookInfo = ((source, book) async => book);
    tocOf(3);
    await tester.longPress(gridBook());
    await tester.pumpAndSettle();
    await tester.tap(find.text('换书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();

    expect(find.byType(BookshelfPage), findsOneWidget);
    expect(find.text('已换到书源乙'), findsOneWidget);
    expect(find.text('更新失败'), findsNothing);
  });

  testWidgets('书源已删除：不请求网络，标出书源不存在；书架上的书保留', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.repository.delete({SimpleBook.sourceUrl});
    await pump(tester);
    expect(find.text('三体'), findsWidgets);
    await pullToRefresh(tester);
    await tester.pumpAndSettle();
    expect(services.engine.calls, isEmpty);
    expect(find.text('书源不存在'), findsNWidgets(2));
  });

  testWidgets('更新中显示进度，停止后原目录不变', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    final pending = Completer<TocResult>();
    services.engine.onChapterList = (source, book) => pending.future;
    await pump(tester);
    await pullToRefresh(tester);
    // 下拉指示器回弹的动画结束后才开始刷新；目录请求一直不返回，等不到 pumpAndSettle
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
}
