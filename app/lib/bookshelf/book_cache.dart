import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_cache.dart';
import '../library/content_source.dart';
import '../library/providers.dart';
import '../reader/chapter_format.dart';
import '../storage/database.dart';

/// 缓存的范围（book-cache「发起缓存」）：从当前章（含）往后，或者整本目录。
enum CacheRange { fromCurrent, all }

/// 发起缓存前的计数（add-book-cache 设计 D4）：不是卷的章节总数、已缓存的章数，以及每个范围里还没缓存的章节下标。
typedef CachePlan = ({int total, int cached, Map<CacheRange, List<int>> pending});

/// 一本书这次缓存的进度：要缓存的章数、有结果的章数（含失败）、失败的章数、是否还在进行。
typedef BookCacheProgress = ({int total, int done, int failed, bool running});

/// 缓存全本（book-cache，add-book-cache 设计 D2）：app 生命周期，离开页面不中断。状态是书的地址 → 进度，
/// 只有发起过缓存的书在里面；结束后保留到下次发起或 app 重启，缓存管理页据此显示失败数。
final class BookCacheController extends Notifier<Map<String, BookCacheProgress>> {
  final Map<String, _Job> _jobs = {};

  @override
  Map<String, BookCacheProgress> build() => const {};

  /// 这本书的计数：目录里不是卷、还没缓存的章节，按范围分开。
  Future<CachePlan> plan(ShelfBook book) async {
    final db = ref.read(databaseProvider);
    final toc = await db.chaptersOf(book.bookUrl);
    final cached = await db.cachedChapterUrls(book.bookUrl);
    final readable = [for (final chapter in toc) if (!chapter.isVolume) chapter];
    final missing = [for (final chapter in readable) if (!cached.contains(chapter.url)) chapter.idx];
    return (
      total: readable.length,
      cached: readable.length - missing.length,
      pending: {CacheRange.all: missing, CacheRange.fromCurrent: [for (final index in missing) if (index >= book.durChapterIndex) index]},
    );
  }

  /// 缓存这本书 [range] 里还没缓存的章节；这本书正在缓存时，不在队列里的章节并入（设计 D2）。
  Future<void> start(ShelfBook book, CacheRange range) async {
    final indices = (await plan(book)).pending[range]!;
    final toc = await ref.read(databaseProvider).chaptersOf(book.bookUrl);
    final running = _jobs[book.bookUrl];
    final job = running != null && running.running ? running : _jobs[book.bookUrl] = _Job();
    final added = [for (final index in indices) if (job.queued.add(index)) index];
    if (added.isEmpty) return _publish(book.bookUrl, job);
    job.total += added.length;
    final caching = ref.read(contentSourceProvider).cacheChapters(book, toc, added);
    job.cachings.add(caching);
    _publish(book.bookUrl, job);
    unawaited(_consume(book, toc, job, caching));
  }

  /// 停止这本书的缓存：没完成的章节不再请求，已写入的保留（书移出书架、换书源时也调用）。
  void stop(String bookUrl) {
    final job = _jobs[bookUrl];
    if (job == null || !job.running) return;
    job.stopped = true;
    for (final caching in job.cachings) {
      caching.stop();
    }
    _publish(bookUrl, job);
  }

  Future<void> _consume(ShelfBook book, List<TocChapter> toc, _Job job, ChapterCaching caching) async {
    await for (final result in caching.results) {
      if (job.stopped) return;
      if (result.text case final text?) {
        await _save(book, toc[result.index], text);
      } else {
        job.failed++;
      }
      job.done++;
      _publish(book.bookUrl, job);
    }
  }

  /// 写正文缓存（原文，和阅读时一样），再逐张下载正文里的图片；图片失败不算这一章失败（设计 D3）。
  Future<void> _save(ShelfBook book, TocChapter chapter, ChapterText text) async {
    final db = ref.read(databaseProvider);
    final saved = await db.transaction(() async {
      if (await db.getBook(book.bookUrl) == null) return false;
      await db.putContent(ContentRow(bookUrl: book.bookUrl, chapterUrl: chapter.url, title: text.title, content: text.content));
      return true;
    });
    if (!saved) return;
    final source = ref.read(contentSourceProvider);
    for (final src in imageSourcesOf(formatChapter(text.title, text.content))) {
      try {
        await cacheContentImage(db, source, book, src);
      } catch (e) {
        log('缓存正文图片失败：$src', error: e, name: 'book-cache');
      }
    }
  }

  void _publish(String bookUrl, _Job job) =>
      state = {...state, bookUrl: (total: job.total, done: job.done, failed: job.failed, running: job.running)};
}

/// 一本书的一次缓存：可以多次并入新的章节，每次并入一个 [ChapterCaching]。
final class _Job {
  final Set<int> queued = {};
  final List<ChapterCaching> cachings = [];
  int total = 0;
  int done = 0;
  int failed = 0;
  bool stopped = false;

  bool get running => !stopped && done < total;
}

final bookCacheProvider = NotifierProvider<BookCacheController, Map<String, BookCacheProgress>>(BookCacheController.new);
