import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/bookshelf/bookshelf_page.dart';
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

  testWidgets('空书架提示去搜索', (tester) async {
    await pump(tester);
    expect(find.text('书架是空的，去搜索添加吧'), findsOneWidget);
  });

  testWidgets('显示书名、作者、最新章节和未读章节数', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.db.saveProgress(SimpleBook.bookUrl, index: 89, url: '/89.html', title: '第89章', position: 0, now: DateTime(2026));
    await pump(tester);
    expect(find.text('三体'), findsOneWidget);
    expect(find.text('刘慈欣 · 第99章'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('点击直接打开阅读页，从保存的进度继续', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.tap(find.text('三体'));
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect((reader.bookUrl, reader.startAt), (SimpleBook.bookUrl, null));
  });

  testWidgets('确认后移出书架', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await pump(tester);
    await tester.tap(find.byTooltip('更多'));
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
    await tester.fling(find.text('三体'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(services.engine.calls, ['toc ${SimpleBook.bookUrl}']);
    expect(find.text('刘慈欣 · 第101章'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterIndex, 99);
  });

  testWidgets('更新失败保留原目录，书上有失败标记', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    services.engine.onChapterList = (source, book) => Future.error(const HostCallException('连接超时'));
    await pump(tester);
    await tester.tap(find.byTooltip('更新目录'));
    await tester.pumpAndSettle();
    expect(find.text('更新失败'), findsOneWidget);
    await tester.tap(find.text('更新失败'));
    await tester.pump();
    expect(find.text('网络错误：连接超时'), findsOneWidget);
    expect(await services.db.chaptersOf(SimpleBook.bookUrl), hasLength(100));
    expect(find.text('刘慈欣 · 第99章'), findsOneWidget);
  });

  testWidgets('书源已删除：不请求网络，标出书源不存在；书架上的书保留', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    await services.repository.delete({SimpleBook.sourceUrl});
    await pump(tester);
    expect(find.text('三体'), findsOneWidget);
    await tester.tap(find.byTooltip('更新目录'));
    await tester.pumpAndSettle();
    expect(services.engine.calls, isEmpty);
    expect(find.text('书源不存在'), findsOneWidget);
  });

  testWidgets('更新中显示进度，停止后原目录不变', (tester) async {
    await services.shelveSimpleBook(chapters: 100);
    final pending = Completer<TocResult>();
    services.engine.onChapterList = (source, book) => pending.future;
    await pump(tester);
    await tester.tap(find.byTooltip('更新目录'));
    await tester.pump();
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
