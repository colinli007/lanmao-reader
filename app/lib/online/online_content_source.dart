import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/content_source.dart';
import '../storage/database.dart';
import 'batch.dart';
import 'book_mapping.dart';
import 'errors.dart';
import 'source_engine.dart';
import 'source_repository.dart';

/// 书架和阅读器的在线内容来源：用书源执行目录、正文链路。停用的书源照样能用（只影响搜索）。
final class OnlineContentSource implements BookContentSource {
  OnlineContentSource(this._engine, this._sources);

  final SourceEngine _engine;
  final SourceRepository _sources;

  @override
  bool hasSource(String origin) => _sources[origin] != null;

  @override
  Future<ChapterText> loadContent(ShelfBook book, TocChapter chapter, {TocChapter? next}) async {
    final entry = _sources[book.origin];
    if (entry == null) throw const ContentLoadException.sourceMissing();
    try {
      final content = await _engine.content(
        entry.source,
        engineBookOf(book),
        engineChapterOf(chapter),
        nextChapterUrl: next == null ? null : chapterAbsoluteUrl(engineChapterOf(next)),
      );
      return (title: content.title, content: content.content);
    } catch (e) {
      throw ContentLoadException(describeError(e));
    }
  }

  @override
  ShelfRefresh refreshShelf(List<ShelfBook> books) => _ShelfRefresh(this, books);
}

final class _ShelfRefresh implements ShelfRefresh {
  _ShelfRefresh(OnlineContentSource owner, List<ShelfBook> books) {
    final pending = [
      for (final book in books)
        _refresh(owner, book).then((result) {
          if (!_batch.isStopped) _results.add(result);
        }, onError: (Object _) {}), // 只有停止时的取消错误会到这里
    ];
    unawaited(Future.wait(pending).whenComplete(_results.close));
  }

  final Batch _batch = Batch();
  final StreamController<TocRefreshResult> _results = StreamController();

  @override
  Stream<TocRefreshResult> get results => _results.stream;

  @override
  void stop() {
    _batch.stop();
    unawaited(_results.close());
  }

  Future<TocRefreshResult> _refresh(OnlineContentSource owner, ShelfBook book) async {
    final entry = owner._sources[book.origin];
    if (entry == null) return TocSourceMissing(book.bookUrl);
    try {
      final result = await owner._engine.chapterList(entry.source, engineBookOf(book), batch: _batch);
      return TocRefreshed(book.bookUrl, tocUpdateOf(result));
    } on TaskCancelledException {
      rethrow;
    } catch (e) {
      return TocRefreshFailed(book.bookUrl, describeError(e));
    }
  }
}
