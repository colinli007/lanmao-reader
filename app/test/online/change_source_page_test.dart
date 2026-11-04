import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/change_source_page.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

/// bookshelf「换书源」「换书源后定位当前章节」、app-storage「换书源时的数据」：书架上的《三体》来自书源甲（SimpleBook），
/// 另有书源乙、丙。乙、丙的目录前面多一个卷，章节名用中文数字（「第三章」），所以按章节编号对齐时序号加 1。
void main() {
  late TestServices services;
  const b = 'https://b.com', c = 'https://c.com';
  const names = ['零', '一', '二', '三', '四', '五'];

  /// 按书源地址替换搜索结果；没有替换的乙、丙返回《三体》（刘慈欣），甲返回 SimpleBook。
  late Map<String, List<SearchBook> Function(String source)> results;

  SearchBook found(String source, {String name = '三体', String author = '刘慈欣', int id = 1}) =>
      SearchBook(bookUrl: '$source/book/$id', origin: source, originName: source == b ? '书源乙' : '书源丙')
        ..name = name
        ..author = author
        ..latestChapterTitle = '$source 的最新章';

  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook();
    await services.shelveSimpleBook();
    await services.addSources([
      {'bookSourceUrl': b, 'bookSourceName': '书源乙', 'searchUrl': '/s'},
      {'bookSourceUrl': c, 'bookSourceName': '书源丙', 'searchUrl': '/s'},
    ]);
    results = {};
    final engine = services.engine;
    final original = (search: engine.onSearch!, info: engine.onBookInfo!, toc: engine.onChapterList!);
    engine
      ..onSearch = ((source, key) async =>
          results[source.bookSourceUrl]?.call(source.bookSourceUrl) ??
          (source.bookSourceUrl == SimpleBook.sourceUrl ? await original.search(source, key) : [found(source.bookSourceUrl)]))
      ..onBookInfo = ((source, book) => source.bookSourceUrl == SimpleBook.sourceUrl ? original.info(source, book) : Future.value(book))
      ..onChapterList = ((source, book) async {
        if (source.bookSourceUrl == SimpleBook.sourceUrl) return original.toc(source, book);
        return (
          book: book,
          chapters: [
            BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
              ..index = 0
              ..title = '正文卷'
              ..url = '/v'
              ..isVolume = true,
            for (var i = 0; i < 5; i++)
              BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
                ..index = i + 1
                ..title = '第${names[i]}章'
                ..url = '/c$i.html',
          ],
        );
      });
  });
  tearDown(() => services.db.close());

  /// 换书源页面压在一个空页面上；[changed] 是页面返回的新书籍地址。
  String? changed;
  Future<void> open(WidgetTester tester) async {
    changed = null;
    await tester.pumpWidget(
      services.app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => changed = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const ChangeSourcePage(bookUrl: SimpleBook.bookUrl)),
              ),
              child: const Text('换源'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('换源'));
    await tester.pumpAndSettle();
  }

  Future<void> readTo(int index, int position) async {
    final chapter = (await services.db.chaptersOf(SimpleBook.bookUrl))[index];
    await services.db.saveProgress(SimpleBook.bookUrl, index: index, url: chapter.url, title: chapter.title, position: position, now: DateTime(2026, 3));
  }

  testWidgets('只列同名同作者的结果', (tester) async {
    results = {
      b: (s) => [found(s, name: ' 三体 ', author: ' 刘慈欣 ')],
      c: (s) => [found(s, name: '三体2'), found(s, author: '佚名', id: 2)],
    };
    await open(tester);
    expect(find.text('书源甲'), findsOneWidget);
    expect(find.text('书源乙'), findsOneWidget);
    expect(find.text('书源丙'), findsNothing);
    expect(find.text('搜索结束，共 2 个候选'), findsOneWidget);
    expect(await services.db.select(services.db.searchKeywords).get(), isEmpty, reason: '换书源按书名搜，不记入搜索历史');
  });

  testWidgets('当前书源和已在书架的不能选', (tester) async {
    final other = found(b);
    await services.db.saveBrowsingBook(
      ShelfBook(bookUrl: other.bookUrl, origin: b, originName: '书源乙', name: '三体', author: '刘慈欣', durChapterIndex: 0, durChapterPos: 0, inShelf: false, sourceData: '{}'),
      const [],
    );
    await services.db.addToShelf(other.bookUrl, DateTime(2026));
    await open(tester);
    expect(find.text('当前'), findsOneWidget);
    expect(find.text('已在书架'), findsOneWidget);
    await tester.tap(find.text('书源甲'));
    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();
    expect(services.engine.calls.where((call) => call.startsWith('info')), isEmpty);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    expect(changed, '$c/book/1');
  });

  testWidgets('离开时停止搜索', (tester) async {
    final pending = Completer<List<SearchBook>>();
    final original = services.engine.onSearch!;
    services.engine.onSearch = (source, key) => source.bookSourceUrl == c ? pending.future : original(source, key);
    await open(tester);
    expect(find.text('已完成 2/3 个书源'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(services.engine.batches.toSet().single.isStopped, isTrue);
  });

  testWidgets('没有可以搜索的书源时提示，不发起搜索', (tester) async {
    await services.repository.setEnabled({SimpleBook.sourceUrl, b, c}, false);
    await open(tester);
    expect(find.text('没有可以搜索的书源，先去导入或启用书源'), findsOneWidget);
    expect(services.engine.calls, isEmpty);
  });

  testWidgets('换源成功：书架上只有新书，位置不变，进度按章节编号对齐，章内位置不变', (tester) async {
    await readTo(3, 40);
    // 书架上另有一本更早读过的书，换源后《三体》仍排在它前面
    await services.db.saveBrowsingBook(
      ShelfBook(bookUrl: 'x', origin: b, originName: '书源乙', name: '球状闪电', author: '刘慈欣', durChapterIndex: 0, durChapterPos: 0, inShelf: false, sourceData: '{}'),
      const [],
    );
    await services.db.addToShelf('x', DateTime(2026));
    await services.db.saveProgress('x', index: 0, url: '/0', title: '第0章', position: 0, now: DateTime(2026, 1));
    final before = (await services.db.getBook(SimpleBook.bookUrl))!;
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();

    expect(changed, '$c/book/1');
    expect([for (final entry in await services.db.shelf()) entry.book.bookUrl], ['$c/book/1', 'x']);
    final book = (await services.db.getBook('$c/book/1'))!;
    expect((book.originName, book.latestChapterTitle), ('书源丙', '第四章'));
    expect((book.durChapterIndex, book.durChapterUrl, book.durChapterTitle, book.durChapterPos), (4, '/c3.html', '第三章', 40));
    expect((book.addedAt, book.lastReadAt), (before.addedAt, before.lastReadAt));
    expect(await services.db.getBook(SimpleBook.bookUrl), isNull);
  });

  testWidgets('对不上时保留原序号，从章首开始', (tester) async {
    await readTo(3, 40);
    final original = services.engine.onChapterList!;
    services.engine.onChapterList = (source, book) async {
      final result = await original(source, book);
      return (book: result.book, chapters: [for (final chapter in result.chapters) chapter..title = '番外${chapter.index}']);
    };
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    final book = (await services.db.getBook('$c/book/1'))!;
    expect((book.durChapterIndex, book.durChapterPos), (3, 0));
  });

  testWidgets('换源失败保持原样，可以另选一个候选', (tester) async {
    await readTo(2, 10);
    final original = services.engine.onChapterList!;
    services.engine.onChapterList = (source, book) =>
        source.bookSourceUrl == c ? Future.error(const HostCallException('Connection refused')) : original(source, book);
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    expect(find.text('网络错误：Connection refused'), findsOneWidget);
    expect(changed, isNull);
    final kept = (await services.db.getBook(SimpleBook.bookUrl))!;
    expect((kept.inShelf, kept.durChapterIndex, kept.durChapterPos), (true, 2, 10));
    expect(await services.db.chaptersOf(SimpleBook.bookUrl), hasLength(5));

    await tester.tap(find.text('书源乙'));
    await tester.pumpAndSettle();
    expect(changed, '$b/book/1');
  });

  testWidgets('加载中途返回时不写入', (tester) async {
    final pending = Completer<Book>();
    services.engine.onBookInfo = (source, book) => pending.future;
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    pending.complete(found(c).toBook());
    await tester.pumpAndSettle();
    expect((await services.db.getBook(SimpleBook.bookUrl))?.inShelf, isTrue);
    expect(await services.db.getBook('$c/book/1'), isNull);
  });

  testWidgets('书源已删除的书也能换', (tester) async {
    await services.repository.delete({SimpleBook.sourceUrl});
    await open(tester);
    expect(find.text('当前'), findsNothing);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    expect((await services.db.getBook('$c/book/1'))?.originName, '书源丙');
  });

  testWidgets('没读过的书换源后仍没有阅读进度', (tester) async {
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    final book = (await services.db.getBook('$c/book/1'))!;
    expect((book.durChapterIndex, book.durChapterUrl, book.durChapterPos), (0, null, 0));
  });

  testWidgets('新书源已缓存的正文保留，书源级状态不变', (tester) async {
    await readTo(3, 0);
    // 以前浏览过书源丙的这本书，读过对齐后的那一章
    final browsed = found(c);
    await services.db.saveBrowsingBook(
      ShelfBook(bookUrl: browsed.bookUrl, origin: c, originName: '书源丙', name: '三体', author: '刘慈欣', durChapterIndex: 0, durChapterPos: 0, inShelf: false, sourceData: '{}'),
      const [],
    );
    await services.db.putContent(ContentRow(bookUrl: browsed.bookUrl, chapterUrl: '/c3.html', title: '第三章', content: '缓存的正文'));
    await services.db.putSourceKv('kv', 'v', null);
    await open(tester);
    await tester.tap(find.text('书源丙'));
    await tester.pumpAndSettle();
    expect(await services.db.loadSourceKv(DateTime(2026)), [const SourceKvRow(key: 'kv', value: 'v')]);

    services.engine.calls.clear();
    await tester.pumpWidget(services.app(ReaderPage(bookUrl: browsed.bookUrl)));
    await tester.pumpAndSettle();
    expect(services.engine.calls, isNot(contains('content /c3.html')));
  });
}

