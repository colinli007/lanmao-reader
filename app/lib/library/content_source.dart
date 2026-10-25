import '../storage/database.dart';

/// 书架和阅读器取目录和正文的接口（设计 D1），由书源模块实现；书架、阅读器只认 `storage/` 的模型。
abstract interface class BookContentSource {
  /// 这本书的书源还在（停用的也算在）。
  bool hasSource(String origin);

  /// 执行正文链路。[next] 是下一章，多页正文遇到它时停止。失败（包括书源不存在）时抛出 [ContentLoadException]。
  Future<ChapterText> loadContent(ShelfBook book, TocChapter chapter, {TocChapter? next});

  /// 按替换净化规则处理一章的章节名和正文（reader「替换净化」，add-replace-rules 设计 D6）。不抛出错误。
  Future<Purified> purify(ShelfBook book, ChapterText text);

  /// 更新这些书的目录：每本书完成时产生一个结果，全部完成或 [ShelfRefresh.stop] 之后结束。
  ShelfRefresh refreshShelf(List<ShelfBook> books);
}

typedef ChapterText = ({String title, String content});

/// 处理后的章节，以及这次因为超时被停用的规则名。
typedef Purified = ({ChapterText text, List<String> disabled});

/// 目录链路的结果：新目录，以及要写回书籍的最新章节名和书源数据。
typedef TocUpdate = ({String? latestChapterTitle, String sourceData, List<TocChapter> chapters});

abstract interface class ShelfRefresh {
  Stream<TocRefreshResult> get results;

  /// 停止：没完成的书不再产生结果，[results] 随即结束。
  void stop();
}

sealed class TocRefreshResult {
  const TocRefreshResult(this.bookUrl);

  final String bookUrl;
}

final class TocRefreshed extends TocRefreshResult {
  const TocRefreshed(super.bookUrl, this.update);

  final TocUpdate update;
}

final class TocRefreshFailed extends TocRefreshResult {
  const TocRefreshFailed(super.bookUrl, this.message);

  final String message;
}

final class TocSourceMissing extends TocRefreshResult {
  const TocSourceMissing(super.bookUrl);
}

/// 取正文失败，[message] 是给用户看的原因。
final class ContentLoadException implements Exception {
  const ContentLoadException(this.message);

  const ContentLoadException.sourceMissing() : message = '书源不存在';

  final String message;

  @override
  String toString() => message;
}
