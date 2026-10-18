import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import 'batch.dart';

/// 四条链路的执行方。界面和控制器只依赖这个接口，测试换成假的实现。
abstract interface class SourceEngine {
  /// 批量任务，经限流器提交。
  Future<List<SearchBook>> search(BookSource source, String key, Batch batch);

  Future<Book> bookInfo(BookSource source, Book book);

  /// [batch] 不为空时是批量任务（书架更新），经限流器提交。
  Future<TocResult> chapterList(BookSource source, Book book, {Batch? batch});

  Future<ChapterContent> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl});
}

/// 在 worker 池上执行。批量任务同时最多 [batchLimit] 个（池大小减 2，留给交互任务），交互任务直接提交（设计 D6）。
final class PoolSourceEngine implements SourceEngine {
  PoolSourceEngine(this._pool, {int batchLimit = 4}) : _limiter = BatchLimiter(batchLimit);

  final WorkerPool _pool;
  final BatchLimiter _limiter;

  @override
  Future<List<SearchBook>> search(BookSource source, String key, Batch batch) =>
      _limiter.run(batch, (token) => _pool.run(searchTask(source, key), cancelToken: token));

  @override
  Future<Book> bookInfo(BookSource source, Book book) => _pool.run(bookInfoTask(source, book));

  @override
  Future<TocResult> chapterList(BookSource source, Book book, {Batch? batch}) => batch == null
      ? _pool.run(chapterListTask(source, book))
      : _limiter.run(batch, (token) => _pool.run(chapterListTask(source, book), cancelToken: token));

  @override
  Future<ChapterContent> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl}) =>
      _pool.run(contentTask(source, book, chapter, nextChapterUrl: nextChapterUrl));
}
