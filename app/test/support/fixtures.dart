import 'package:novel_reader/storage/database.dart';

ShelfBook book(String url, {String name = '书', bool inShelf = false, DateTime? addedAt, DateTime? lastReadAt, int dur = 0}) =>
    ShelfBook(
      bookUrl: url,
      origin: 'https://s.com',
      originName: '书源',
      name: name,
      author: '作者',
      durChapterIndex: dur,
      durChapterPos: 0,
      inShelf: inShelf,
      addedAt: addedAt,
      lastReadAt: lastReadAt,
      sourceData: '{}',
    );

TocChapter chapter(String bookUrl, int idx, {String? url, bool volume = false}) => TocChapter(
  bookUrl: bookUrl,
  idx: idx,
  url: url ?? '/$idx.html',
  title: '第$idx章',
  isVolume: volume,
  isVip: false,
  isPay: false,
  sourceData: '{}',
);

List<TocChapter> toc(String bookUrl, int count) => [for (var i = 0; i < count; i++) chapter(bookUrl, i)];
