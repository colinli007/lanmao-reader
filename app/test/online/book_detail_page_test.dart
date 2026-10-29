import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/book_detail_page.dart';
import 'package:novel_reader/online/search_controller.dart';
import 'package:novel_reader/reader/reader_page.dart';
import 'package:novel_reader/reader/toc_page.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook();
  });
  tearDown(() => services.db.close());

  MergedBook merged([List<String> sources = const [SimpleBook.sourceUrl]]) {
    final book = MergedBook('三体', '刘慈欣');
    for (final url in sources) {
      book.results.add((
        source: services.repository[url]!,
        book: SearchBook(bookUrl: '$url/book/1', origin: url, originName: services.repository[url]!.source.bookSourceName)
          ..name = '三体'
          ..author = '刘慈欣',
      ));
    }
    return book;
  }

  testWidgets('依次执行详情和目录，显示书籍信息、章节数和最新章节', (tester) async {
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    expect(services.engine.calls, ['info ${SimpleBook.bookUrl}', 'toc ${SimpleBook.bookUrl}']);
    // 小标题和简介内容（测试里的简介就是「简介」两个字）
    expect(find.text('简介'), findsNWidgets(2));
    expect(find.text('书源甲'), findsOneWidget);
    expect(find.text('共 5 章'), findsOneWidget);
    expect(find.text('第4章'), findsOneWidget);
    // 目录加载后作为浏览中的书落盘
    expect((await services.db.getBook(SimpleBook.bookUrl))?.inShelf, isFalse);
  });

  testWidgets('详情失败时显示原因，重试再执行一次详情链路', (tester) async {
    var fail = true;
    final original = services.engine.onBookInfo!;
    services.engine.onBookInfo = (source, book) => fail ? Future.error(RuleException('详情页打不开')) : original(source, book);
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    expect(find.textContaining('规则错误：详情页打不开'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(services.engine.calls.where((c) => c.startsWith('info')), hasLength(2));
    expect(find.text('共 5 章'), findsOneWidget);
  });

  testWidgets('已在书架上时显示书架上的信息，不重新执行详情链路', (tester) async {
    await services.shelveSimpleBook();
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    expect(services.engine.calls, isEmpty);
    expect(find.text('已在书架'), findsWidgets);
  });

  testWidgets('第一个书源失败后换书源', (tester) async {
    await services.addSources([{'bookSourceUrl': 'https://b.com', 'bookSourceName': '书源乙', 'searchUrl': '/s'}]);
    final original = services.engine.onBookInfo!;
    services.engine.onBookInfo = (source, book) =>
        source.bookSourceUrl == SimpleBook.sourceUrl ? Future.error(RuleException('坏了')) : original(source, book);
    await tester.pumpWidget(services.app(BookDetailPage.search(merged([SimpleBook.sourceUrl, 'https://b.com']))));
    await tester.pumpAndSettle();
    expect(find.textContaining('坏了'), findsOneWidget);
    await tester.tap(find.text('共 2 个书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();
    expect(find.text('书源乙'), findsOneWidget);
    expect(find.text('共 5 章'), findsOneWidget);
  });

  testWidgets('目录为空时仍显示书籍信息，目录位置显示原因和重试', (tester) async {
    services.engine.onChapterList = (source, book) => Future.error(RuleException('目录为空', sourceName: '书源甲', field: 'ruleToc.chapterList'));
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    // 小标题和简介内容（测试里的简介就是「简介」两个字）
    expect(find.text('简介'), findsNWidgets(2));
    expect(find.text('规则错误：目录为空（书源甲 ruleToc.chapterList）'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('卷显示为分组标题、不能点击；从目录选章打开阅读页', (tester) async {
    services.engine.onChapterList = (source, book) async => (
      book: book,
      chapters: [
        for (var i = 0; i < 12; i++)
          BookChapter(bookUrl: book.bookUrl, baseUrl: '${SimpleBook.bookUrl}/toc')
            ..index = i
            ..title = i == 0 ? '第一卷' : '第$i章'
            ..url = i == 0 ? '第一卷0' : '/$i.html'
            ..isVolume = i == 0,
      ],
    );
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('共 11 章'), 100);
    await tester.tap(find.text('共 11 章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一卷'));
    await tester.pumpAndSettle();
    expect(find.byType(TocPage), findsOneWidget);
    await tester.ensureVisible(find.text('第10章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第10章'));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).startAt, 10);
  });

  testWidgets('加入书架；开始阅读从第一个不是卷的章节开始', (tester) async {
    await tester.pumpWidget(services.app(BookDetailPage.search(merged())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入书架'));
    await tester.pumpAndSettle();
    expect((await services.db.getBook(SimpleBook.bookUrl))?.inShelf, isTrue);
    expect(find.text('已在书架'), findsWidgets);
    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).startAt, 0);
  });

  testWidgets('有阅读进度时是「继续阅读」，从进度继续', (tester) async {
    await services.shelveSimpleBook();
    await services.db.saveProgress(SimpleBook.bookUrl, index: 2, url: '/2.html', title: '第2章', position: 0, now: DateTime(2026));
    await tester.pumpWidget(services.app(const BookDetailPage.shelf(SimpleBook.bookUrl)));
    await tester.pumpAndSettle();
    expect(find.text('开始阅读'), findsNothing);
    await tester.tap(find.text('继续阅读'));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).startAt, isNull);
  });

  testWidgets('从书架打开时换源：回到详情页，显示新书源名和目录，仍标明已在书架', (tester) async {
    await services.shelveSimpleBook();
    await services.addSources([{'bookSourceUrl': 'https://b.com', 'bookSourceName': '书源乙', 'searchUrl': '/s'}]);
    services.engine.onSearch = (source, key) async => [
      SearchBook(bookUrl: '${source.bookSourceUrl}/book/1', origin: source.bookSourceUrl, originName: source.bookSourceName)
        ..name = '三体'
        ..author = '刘慈欣',
    ];
    await tester.pumpWidget(services.app(const BookDetailPage.shelf(SimpleBook.bookUrl)));
    await tester.pumpAndSettle();
    expect(find.text('书源甲'), findsOneWidget);
    await tester.tap(find.text('换书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.text('书源乙'), findsOneWidget);
    expect(find.text('共 5 章'), findsOneWidget);
    expect(find.text('已在书架'), findsWidgets);
  });
}
