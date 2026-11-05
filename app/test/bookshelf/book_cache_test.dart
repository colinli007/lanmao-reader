import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/bookshelf/book_cache.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:rule_engine/rule_engine.dart';

import '../reader/content_images_test.dart' show png;
import '../support/test_app.dart';

// book-cache「发起缓存」「下载章节」：控制器
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestServices services;
  late ProviderContainer container;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 10, paragraphs: 2);
    await services.shelveSimpleBook(chapters: 10);
    container = ProviderContainer(overrides: services.overrides);
  });
  tearDown(() async {
    container.dispose();
    await services.db.close();
  });

  BookCacheController controller() => container.read(bookCacheProvider.notifier);
  Future<ShelfBook> book() async => (await services.db.getBook(SimpleBook.bookUrl))!;
  BookCacheProgress? progress() => container.read(bookCacheProvider)[SimpleBook.bookUrl];

  /// 等这本书的缓存结束。
  Future<void> finished() async {
    for (var i = 0; i < 200 && (progress()?.running ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> cache(int index) async {
    final chapter = (await services.db.chaptersOf(SimpleBook.bookUrl))[index];
    await services.db.putContent(ContentRow(bookUrl: SimpleBook.bookUrl, chapterUrl: chapter.url, title: chapter.title, content: '正文'));
  }

  test('计数：不含卷，已缓存的不算在范围里；从当前章往后含当前章', () async {
    for (final i in [0, 1, 2, 3, 7]) {
      await cache(i);
    }
    await services.db.saveProgress(SimpleBook.bookUrl, index: 3, url: '/3.html', title: '第3章', position: 0, now: DateTime(2026));
    final plan = await controller().plan(await book());
    expect((plan.total, plan.cached), (10, 5));
    expect(plan.pending[CacheRange.fromCurrent], [4, 5, 6, 8, 9]);
    expect(plan.pending[CacheRange.all], [4, 5, 6, 8, 9]);
  });

  test('缓存后正文和其中的图片都在缓存里，失败的章节算进失败数', () async {
    final picture = await png(40, 30);
    final original = services.engine.onContent!;
    services.engine
      ..onContent = ((source, b, chapter, next) async => switch (chapter.title) {
        '第2章' => ChapterContent('有图<img src="https://a.com/2.png">的一章', title: chapter.title),
        '第5章' => throw Exception('404'),
        _ => await original(source, b, chapter, next),
      })
      ..onImage = ((source, b, src) async => picture);
    await controller().start(await book(), CacheRange.all);
    expect(progress()!.running, isTrue);
    await finished();
    expect(progress(), (total: 10, done: 10, failed: 1, running: false));
    final counts = await services.db.watchCacheCounts().first;
    expect(counts[SimpleBook.bookUrl], (cached: 9, total: 10));
    expect(await services.db.getContentImage(SimpleBook.bookUrl, 'https://a.com/2.png'), picture);
  });

  test('正在缓存时再次发起：只并入不在队列里的章节；停止后不再写入', () async {
    final release = Completer<void>();
    final original = services.engine.onContent!;
    services.engine.onContent = (source, b, chapter, next) async {
      await release.future;
      return original(source, b, chapter, next);
    };
    await services.db.saveProgress(SimpleBook.bookUrl, index: 6, url: '/6.html', title: '第6章', position: 0, now: DateTime(2026));
    await controller().start(await book(), CacheRange.fromCurrent);
    expect(progress()!.total, 4);
    await controller().start(await book(), CacheRange.all);
    expect(progress()!.total, 10, reason: '第 6 到 9 章已经在队列里');
    controller().stop(SimpleBook.bookUrl);
    expect(progress()!.running, isFalse);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await services.db.watchCacheCounts().first)[SimpleBook.bookUrl]!.cached, 0);
  });
}
