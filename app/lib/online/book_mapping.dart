import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';

import '../library/content_source.dart';
import '../storage/database.dart';

// 引擎模型和存储模型之间的转换（设计 D1）。引擎专用的字段放进不透明的 sourceData，只有这里解读。
// 搜索和详情保存的页面（infoHtml、tocHtml）不落盘：书架更新目录时必须重新请求，才能看到新章节。

/// 浏览中的书：进度为初始值，不在书架上。
ShelfBook shelfBookOf(Book book) => ShelfBook(
  bookUrl: book.bookUrl,
  origin: book.origin,
  originName: book.originName,
  name: book.name,
  author: book.author,
  kind: book.kind,
  coverUrl: book.coverUrl,
  intro: book.intro,
  wordCount: book.wordCount,
  latestChapterTitle: book.latestChapterTitle,
  durChapterIndex: 0,
  durChapterPos: 0,
  inShelf: false,
  sourceData: bookData(book),
);

String bookData(Book book) => jsonEncode({
  'variables': book.variables,
  'tocUrl': book.tocUrl,
  'reverseToc': book.reverseToc,
  'customIntro': book.customIntro,
  'totalChapterNum': book.totalChapterNum,
});

Book engineBookOf(ShelfBook shelf) {
  final data = jsonDecode(shelf.sourceData) as Map<String, Object?>;
  return Book(
      bookUrl: shelf.bookUrl,
      origin: shelf.origin,
      originName: shelf.originName,
      variables: (data['variables'] as Map? ?? const {}).cast<String, String>(),
    )
    ..name = shelf.name
    ..author = shelf.author
    ..kind = shelf.kind
    ..coverUrl = shelf.coverUrl
    ..intro = shelf.intro
    ..wordCount = shelf.wordCount
    ..latestChapterTitle = shelf.latestChapterTitle
    ..tocUrl = data['tocUrl'] as String? ?? ''
    ..reverseToc = data['reverseToc'] as bool? ?? false
    ..customIntro = data['customIntro'] as String?
    ..totalChapterNum = data['totalChapterNum'] as int? ?? 0
    ..durChapterIndex = shelf.durChapterIndex
    ..durChapterTitle = shelf.durChapterTitle;
}

TocChapter tocChapterOf(BookChapter chapter) => TocChapter(
  bookUrl: chapter.bookUrl,
  idx: chapter.index,
  url: chapter.url,
  title: chapter.title,
  isVolume: chapter.isVolume,
  isVip: chapter.isVip,
  isPay: chapter.isPay,
  tag: chapter.tag,
  sourceData: jsonEncode({'baseUrl': chapter.baseUrl, 'variables': chapter.variables, 'reviewImg': chapter.reviewImg}),
);

BookChapter engineChapterOf(TocChapter toc) {
  final data = jsonDecode(toc.sourceData) as Map<String, Object?>;
  return BookChapter(
      bookUrl: toc.bookUrl,
      baseUrl: data['baseUrl'] as String,
      variables: (data['variables'] as Map? ?? const {}).cast<String, String>(),
    )
    ..url = toc.url
    ..title = toc.title
    ..index = toc.idx
    ..isVolume = toc.isVolume
    ..isVip = toc.isVip
    ..isPay = toc.isPay
    ..tag = toc.tag
    ..reviewImg = data['reviewImg'] as String?;
}

/// 最新章节名取目录的最后一章，和 MD3 的 BookChapterList 一致（引擎的目录链路不改它）。
TocUpdate tocUpdateOf(TocResult result) => (
  latestChapterTitle: result.chapters.lastOrNull?.title ?? result.book.latestChapterTitle,
  sourceData: bookData(result.book),
  chapters: [for (final chapter in result.chapters) tocChapterOf(chapter)],
);
