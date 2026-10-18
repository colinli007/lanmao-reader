import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/storage/database.dart';

import '../support/fixtures.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('导入书源：已有的保留位置并替换内容，新的排在最后', () async {
    await db.importSources([(url: 'a', json: '1', enabled: true), (url: 'b', json: '1', enabled: true)]);
    await db.importSources([(url: 'c', json: '2', enabled: false), (url: 'a', json: '2', enabled: false)]);
    final rows = await db.allSources();
    expect([for (final r in rows) (r.url, r.json, r.enabled)], [('a', '2', false), ('b', '1', true), ('c', '2', false)]);
    await db.setSourcesEnabled(['a', 'c'], true);
    await db.deleteSources(['b']);
    expect([for (final r in await db.allSources()) (r.url, r.enabled)], [('a', true), ('c', true)]);
  });

  test('书架排序：最近阅读的在前，没读过的按加入时间排在后面', () async {
    final t = DateTime(2026);
    for (final b in [
      book('never-old', inShelf: true, addedAt: t),
      book('read-old', inShelf: true, addedAt: t, lastReadAt: t.add(const Duration(hours: 1))),
      book('never-new', inShelf: true, addedAt: t.add(const Duration(days: 1))),
      book('read-new', inShelf: true, addedAt: t, lastReadAt: t.add(const Duration(hours: 2))),
      book('browsing'),
    ]) {
      await db.into(db.books).insert(b);
    }
    final shelf = await db.watchShelf().first;
    expect([for (final e in shelf) e.book.bookUrl], ['read-new', 'read-old', 'never-new', 'never-old']);
  });

  test('未读章节数：排在当前章节之后的非卷章节', () async {
    await db.into(db.books).insert(book('b', inShelf: true, dur: 2));
    await db.batch((b) => b.insertAll(db.chapters, [...toc('b', 6), chapter('b', 6, volume: true), chapter('b', 7)]));
    await db.into(db.books).insert(book('empty', inShelf: true));
    final shelf = {for (final e in await db.watchShelf().first) e.book.bookUrl: e.unread};
    expect(shelf, {'b': 4, 'empty': 0});
  });

  test('浏览中的书再次保存时只更新书籍信息和目录，进度和是否在书架不变', () async {
    await db.saveBrowsingBook(book('b', name: '旧'), toc('b', 3));
    await db.saveProgress('b', index: 2, url: '/2.html', title: '第2章', position: 40, now: DateTime(2026));
    await db.addToShelf('b', DateTime(2026));
    await db.saveBrowsingBook(book('b', name: '新'), toc('b', 5));
    final saved = (await db.getBook('b'))!;
    expect((saved.name, saved.inShelf, saved.durChapterIndex, saved.durChapterPos), ('新', true, 2, 40));
    expect(await db.chaptersOf('b'), hasLength(5));
  });

  test('正文缓存按书和章节地址读写', () async {
    await db.putContent(const ContentRow(bookUrl: 'b', chapterUrl: '/1', title: 't', content: 'c1'));
    await db.putContent(const ContentRow(bookUrl: 'b', chapterUrl: '/1', title: 't', content: 'c2'));
    expect((await db.getContent('b', '/1'))?.content, 'c2');
    expect(await db.getContent('b', '/2'), isNull);
  });

  test('书源级状态：载入时删除过期的行', () async {
    final now = DateTime(2026);
    await db.putSourceKv('old', 'v', now);
    await db.putSourceKv('live', 'v', now.add(const Duration(seconds: 1)));
    await db.putSourceKv('forever', 'v', null);
    expect([for (final r in await db.loadSourceKv(now)) r.key]..sort(), ['forever', 'live']);
    expect(await db.select(db.sourceKv).get(), hasLength(2));
  });

  test('Cookie 和设置', () async {
    await db.putCookie('a.com', 'x=1');
    await db.putCookie('b.com', 'y=1');
    await db.putCookie('b.com', null);
    expect(await db.loadCookies(), {'a.com': 'x=1'});
    await db.putSetting('k', '1');
    await db.putSetting('k', '2');
    expect(await db.loadSettings(), {'k': '2'});
  });

}
