import 'dart:typed_data';

import '../storage/database.dart';

/// 书架和阅读器取目录和正文的接口（设计 D1），由书源模块实现；书架、阅读器只认 `storage/` 的模型。
abstract interface class BookContentSource {
  /// 这本书的书源还在（停用的也算在）。
  bool hasSource(String origin);

  /// 执行正文链路。[next] 是下一章，多页正文遇到它时停止。失败（包括书源不存在）时抛出 [ContentLoadException]。
  Future<ChapterText> loadContent(ShelfBook book, TocChapter chapter, {TocChapter? next});

  /// 正文里的一张图片的字节（reader「正文图片」）：[src] 是正文里 `<img>` 的地址，可能带 `,{选项}`。
  /// 失败（包括书源不存在）时抛出 [ContentLoadException]。
  Future<Uint8List> loadImage(ShelfBook book, String src);

  /// 这本书的书源规定的正文图片样式（`ruleContent.imageStyle`），没有时为 null。
  String? imageStyle(ShelfBook book);

  /// 按替换净化规则处理一章的章节名和正文（reader「替换净化」，add-replace-rules 设计 D6）。不抛出错误。
  Future<Purified> purify(ShelfBook book, ChapterText text);

  /// 缓存全本（book-cache「下载章节」，add-book-cache 设计 D1）：对目录 [toc] 里下标为 [indices] 的章节执行正文链路，
  /// 作为批量任务，失败的重试；每章有最终结果时产生一个结果，全部完成或 [ChapterCaching.stop] 之后结束。
  /// 用整本目录是因为多页正文要靠下一章的地址停下。写缓存由调用方做。
  ChapterCaching cacheChapters(ShelfBook book, List<TocChapter> toc, Iterable<int> indices);

  /// 更新这些书的目录：每本书完成时产生一个结果，全部完成或 [ShelfRefresh.stop] 之后结束。
  ShelfRefresh refreshShelf(List<ShelfBook> books);
}

typedef ChapterText = ({String title, String content});

/// 处理后的章节，以及这次因为超时被停用的规则名。
typedef Purified = ({ChapterText text, List<String> disabled});

/// 目录链路的结果：新目录，以及要写回书籍的最新章节名和书源数据。
typedef TocUpdate = ({String? latestChapterTitle, String sourceData, List<TocChapter> chapters});

/// 一章的缓存结果：成功时有 [text]，最终失败时有 [error]（给用户看的原因）。
typedef ChapterCacheResult = ({int index, ChapterText? text, String? error});

abstract interface class ChapterCaching {
  Stream<ChapterCacheResult> get results;

  /// 停止：没完成的章节不再请求，[results] 随即结束。
  void stop();
}

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
