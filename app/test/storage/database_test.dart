import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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

  test('正文缓存统计：章节数和正文的 UTF-8 字节数', () async {
    expect(await db.contentCacheStats(), (chapters: 0, bytes: 0));
    const texts = ['第一章正文', 'abc', '“对话”……'];
    await db.putContent(ContentRow(bookUrl: 'a', chapterUrl: '/0', title: '标题', content: texts[0]));
    await db.putContent(ContentRow(bookUrl: 'a', chapterUrl: '/1', title: '标题', content: texts[1]));
    await db.putContent(ContentRow(bookUrl: 'b', chapterUrl: '/0', title: '标题', content: texts[2]));
    final bytes = texts.fold(0, (sum, t) => sum + utf8.encode(t).length);
    expect(await db.contentCacheStats(), (chapters: 3, bytes: bytes));
  });

  test('清除正文缓存：只删正文，书籍、目录、进度、书源、替换规则、设置、书源级状态和 Cookie 不变', () async {
    await db.importSources([(url: 's', json: '{}', enabled: true)]);
    await db.putReplaceRules([const ReplaceRuleRow(id: 1, json: '{}', enabled: true)]);
    await db.saveBrowsingBook(book('b'), toc('b', 3));
    await db.addToShelf('b', DateTime(2026));
    await db.saveProgress('b', index: 2, url: '/2.html', title: '第2章', position: 40, now: DateTime(2026));
    await db.putContent(const ContentRow(bookUrl: 'b', chapterUrl: '/2.html', title: '第2章', content: '正文'));
    await db.putSetting('k', 'v');
    await db.putSourceKv('kv', 'v', null);
    await db.putCookie('a.com', 'x=1');
    Future<List<Object>> others() async => [
      for (final ResultSetImplementation<HasResultSet, Object> table in [db.sources, db.replaceRules, db.books, db.chapters, db.settings, db.sourceKv, db.cookies])
        await db.select(table).get(),
    ];
    final before = await others();

    await db.clearContents();
    expect(await db.contentCacheStats(), (chapters: 0, bytes: 0));
    expect(await others(), before);
  });

  test('清除正文缓存后数据库文件变小', () async {
    final dir = Directory.systemTemp.createTempSync('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // setUp 的内存数据库也开着
    final fileDb = AppDatabase(NativeDatabase(file));
    addTearDown(fileDb.close);
    final chapter = '正文' * 50000; // 300KB
    for (var i = 0; i < 34; i++) {
      await fileDb.putContent(ContentRow(bookUrl: 'b', chapterUrl: '/$i', title: '第$i章', content: chapter));
    }
    final cached = (await fileDb.contentCacheStats()).bytes;
    final before = file.lengthSync();

    await fileDb.clearContents();
    expect(before - file.lengthSync(), closeTo(cached, cached * 0.05));
  });

  test('换书源：删除旧书的书籍、目录和正文，写入书架上的新书和目录；新地址已有的正文、书源级状态和 Cookie 不变', () async {
    await db.saveBrowsingBook(book('old'), toc('old', 3));
    await db.addToShelf('old', DateTime(2026));
    await db.putContent(const ContentRow(bookUrl: 'old', chapterUrl: '/0.html', title: '第0章', content: '旧'));
    // 新书源上的这本书以前浏览过，读过 2 章
    await db.saveBrowsingBook(book('new'), toc('new', 2));
    await db.putContent(const ContentRow(bookUrl: 'new', chapterUrl: '/0.html', title: '第0章', content: '新0'));
    await db.putContent(const ContentRow(bookUrl: 'new', chapterUrl: '/1.html', title: '第1章', content: '新1'));
    await db.putSourceKv('kv', 'v', null);
    await db.putCookie('a.com', 'x=1');
    Future<List<Object>> kept() async => [await db.select(db.sourceKv).get(), await db.select(db.cookies).get()];
    final before = await kept();

    final moved = book('new', inShelf: true, addedAt: DateTime(2026), lastReadAt: DateTime(2026, 2), dur: 3)
        .copyWith(durChapterUrl: const Value('/3.html'), durChapterTitle: const Value('第3章'), durChapterPos: 40);
    await db.changeSource('old', moved, toc('new', 5));

    expect(await db.getBook('old'), isNull);
    expect(await db.chaptersOf('old'), isEmpty);
    expect(await db.getContent('old', '/0.html'), isNull);
    expect(await db.getBook('new'), moved);
    expect(await db.chaptersOf('new'), hasLength(5));
    expect([for (final url in ['/0.html', '/1.html']) (await db.getContent('new', url))?.content], ['新0', '新1']);
    expect(await kept(), before);
  });

  test('换书源后重启：新书不会当成浏览中的书清掉', () async {
    final dir = Directory.systemTemp.createTempSync('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // setUp 的内存数据库也开着
    var fileDb = AppDatabase(NativeDatabase(file));
    await fileDb.saveBrowsingBook(book('old'), toc('old', 3));
    await fileDb.addToShelf('old', DateTime(2026));
    await fileDb.changeSource('old', book('new', inShelf: true, addedAt: DateTime(2026)), toc('new', 5));
    await fileDb.close();

    fileDb = AppDatabase(NativeDatabase(file));
    addTearDown(fileDb.close);
    await fileDb.purgeBrowsingBooks();
    expect([for (final entry in await fileDb.shelf()) entry.book.bookUrl], ['new']);
    expect(await fileDb.chaptersOf('new'), hasLength(5));
  });

  test('替换规则：同一个 id 整行替换，可以改启用状态和删除', () async {
    await db.putReplaceRules([
      const ReplaceRuleRow(id: 1, json: '{"pattern":"a"}', enabled: true),
      const ReplaceRuleRow(id: 2, json: '{"pattern":"b"}', enabled: true),
    ]);
    await db.putReplaceRules([const ReplaceRuleRow(id: 1, json: '{"pattern":"c"}', enabled: false)]);
    await db.setReplaceRuleEnabled(2, false);
    await db.deleteReplaceRule(1);
    expect(await db.allReplaceRules(), [const ReplaceRuleRow(id: 2, json: '{"pattern":"b"}', enabled: false)]);
  });

  test('从没有替换规则的版本（v1）升级：原有数据都在，替换规则为空、可以写入', () async {
    final dir = Directory.systemTemp.createTempSync('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // setUp 的内存数据库也开着
    var fileDb = AppDatabase(NativeDatabase(file));
    await fileDb.importSources([(url: 's', json: '{}', enabled: true)]);
    await fileDb.saveBrowsingBook(book('b'), toc('b', 3));
    await fileDb.addToShelf('b', DateTime(2026));
    await fileDb.putContent(const ContentRow(bookUrl: 'b', chapterUrl: '/0.html', title: '第0章', content: '正文'));
    await fileDb.putSetting('k', 'v');
    // 退回 v1 的样子：没有 replace_rules 表
    await fileDb.customStatement('DROP TABLE replace_rules');
    await fileDb.customStatement('PRAGMA user_version = 1');
    await fileDb.close();

    fileDb = AppDatabase(NativeDatabase(file));
    addTearDown(fileDb.close);
    expect((await fileDb.allSources()).single.url, 's');
    expect([for (final entry in await fileDb.shelf()) entry.book.bookUrl], ['b']);
    expect((await fileDb.getContent('b', '/0.html'))?.content, '正文');
    expect(await fileDb.loadSettings(), {'k': 'v'});
    expect(await fileDb.allReplaceRules(), isEmpty);
    await fileDb.putReplaceRules([const ReplaceRuleRow(id: 1, json: '{}', enabled: true)]);
    expect(await fileDb.allReplaceRules(), hasLength(1));
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
