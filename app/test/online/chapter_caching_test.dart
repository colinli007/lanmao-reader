import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/storage/database.dart';

import '../support/test_app.dart';

// book-cache「下载章节」：在线实现的批量、重试、停止
void main() {
  late TestServices services;
  late ShelfBook book;
  late List<TocChapter> toc;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 6, paragraphs: 2);
    await services.shelveSimpleBook(chapters: 6);
    book = (await services.db.getBook(SimpleBook.bookUrl))!;
    toc = await services.db.chaptersOf(SimpleBook.bookUrl);
  });
  tearDown(() => services.db.close());

  int contentCalls(String url) => services.engine.calls.where((call) => call == 'content $url').length;

  test('每章作为批量任务执行，成功的带正文', () async {
    final results = await services.contentSource.cacheChapters(book, toc, [1, 2, 3]).results.toList();
    expect([for (final r in results) r.index]..sort(), [1, 2, 3]);
    expect(results.every((r) => r.text != null && r.error == null), isTrue);
    expect(results.firstWhere((r) => r.index == 2).text!.content, contains('第2章第0段'));
    expect(services.engine.batches, hasLength(3), reason: '每章都经批量限流器');
  });

  test('失败的重试，同一章最多请求 3 次', () async {
    final original = services.engine.onContent!;
    final attempts = <String, int>{};
    services.engine.onContent = (source, b, chapter, next) async {
      final n = attempts[chapter.url] = (attempts[chapter.url] ?? 0) + 1;
      if (chapter.title == '第1章' && n < 3) throw Exception('超时');
      if (chapter.title == '第2章') throw Exception('404');
      return original(source, b, chapter, next);
    };
    final results = await services.contentSource.cacheChapters(book, toc, [1, 2]).results.toList();
    final byIndex = {for (final r in results) r.index: r};
    expect(byIndex[1]!.text, isNotNull, reason: '第三次成功');
    expect(byIndex[2]!.error, contains('404'));
    expect(contentCalls(toc[1].url), 3);
    expect(contentCalls(toc[2].url), 3);
  });

  test('停止后结果流结束，没开始的章节不再请求', () async {
    final caching = services.contentSource.cacheChapters(book, toc, [0, 1, 2, 3, 4, 5]);
    final first = await caching.results.first;
    caching.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(first.text, isNotNull);
    expect(services.engine.batches.every((batch) => batch.isStopped), isTrue);
  });

  test('书源不存在时每章都失败，不发请求', () async {
    final missing = book.copyWith(origin: 'https://gone.com');
    final results = await services.contentSource.cacheChapters(missing, toc, [0, 1]).results.toList();
    expect([for (final r in results) r.error], ['书源不存在', '书源不存在']);
    expect(services.engine.calls, isEmpty);
  });
}
