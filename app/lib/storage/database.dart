import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// 书源：导入时的原始 JSON 和启用状态。
@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get url => text()();
  TextColumn get json => text()();
  BoolColumn get enabled => boolean()();

  /// 首次导入的顺序，更新书源时不变。
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {url};
}

/// 书架上的书和浏览中的书（[inShelf] 为假，启动时清理）。
@DataClassName('ShelfBook')
class Books extends Table {
  TextColumn get bookUrl => text()();
  TextColumn get origin => text()();
  TextColumn get originName => text()();
  TextColumn get name => text()();
  TextColumn get author => text()();
  TextColumn get kind => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get intro => text().nullable()();
  TextColumn get wordCount => text().nullable()();
  TextColumn get latestChapterTitle => text().nullable()();

  /// 阅读进度：当前章节的序号、地址、章节名，章内位置是第一个可见段落在排版后正文里的字符偏移。
  IntColumn get durChapterIndex => integer().withDefault(const Constant(0))();
  TextColumn get durChapterUrl => text().nullable()();
  TextColumn get durChapterTitle => text().nullable()();
  IntColumn get durChapterPos => integer().withDefault(const Constant(0))();

  BoolColumn get inShelf => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().nullable()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();

  /// 只有书源模块解读的数据（书籍变量、目录地址等），这里不透明地保存。
  TextColumn get sourceData => text()();

  @override
  Set<Column> get primaryKey => {bookUrl};
}

@DataClassName('TocChapter')
class Chapters extends Table {
  TextColumn get bookUrl => text()();
  IntColumn get idx => integer()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  BoolColumn get isVolume => boolean()();
  BoolColumn get isVip => boolean()();
  BoolColumn get isPay => boolean()();
  TextColumn get tag => text().nullable()();

  /// 只有书源模块解读的数据（章节变量、目录页地址等）。
  TextColumn get sourceData => text()();

  @override
  Set<Column> get primaryKey => {bookUrl, idx};
}

/// 正文缓存，按章节地址（目录链路按地址去重，书内唯一）。
@DataClassName('ContentRow')
class Contents extends Table {
  TextColumn get bookUrl => text()();
  TextColumn get chapterUrl => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();

  @override
  Set<Column> get primaryKey => {bookUrl, chapterUrl};
}

/// 书源级状态（缓存、书源变量、登录头、登录信息），[deadline] 为空时不过期。
@DataClassName('SourceKvRow')
class SourceKv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get deadline => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 持久 Cookie，按注册域名。
@DataClassName('CookieRow')
class Cookies extends Table {
  TextColumn get domain => text()();
  TextColumn get cookie => text()();

  @override
  Set<Column> get primaryKey => {domain};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 书架上的一本书和它的未读章节数（排在当前章节之后的非卷章节数）。
typedef ShelfEntry = ({ShelfBook book, int unread});

/// 已缓存正文的章节数和正文的 UTF-8 字节数。
typedef ContentCacheStats = ({int chapters, int bytes});

@DriftDatabase(tables: [Sources, Books, Chapters, Contents, SourceKv, Cookies, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 应用支持目录下的数据库，在后台 isolate 上执行查询。
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(name: 'novel_reader', native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory)),
  );

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------- 书源

  Future<List<SourceRow>> allSources() => (select(sources)..orderBy([(s) => OrderingTerm(expression: s.position)])).get();

  /// 写入导入的书源：已有的保留位置，新的排在最后。
  Future<void> importSources(List<({String url, String json, bool enabled})> items) => transaction(() async {
    final existing = {for (final row in await select(sources).get()) row.url: row.position};
    var next = existing.values.fold(-1, (max, p) => p > max ? p : max) + 1;
    await batch((b) {
      for (final item in items) {
        final position = existing[item.url] ?? next++;
        b.insert(
          sources,
          SourceRow(url: item.url, json: item.json, enabled: item.enabled, position: position),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  });

  Future<void> setSourcesEnabled(Iterable<String> urls, bool enabled) =>
      (update(sources)..where((s) => s.url.isIn(urls))).write(SourcesCompanion(enabled: Value(enabled)));

  Future<void> deleteSources(Iterable<String> urls) => (delete(sources)..where((s) => s.url.isIn(urls))).go();

  // ---------------------------------------------------------------- 书

  /// 书架：最近阅读的在前；没读过的按加入时间从新到旧，排在读过的后面。
  Stream<List<ShelfEntry>> watchShelf() {
    final (query, read) = _shelfQuery();
    return query.watch().map((rows) => rows.map(read).toList());
  }

  Future<List<ShelfEntry>> shelf() async {
    final (query, read) = _shelfQuery();
    return (await query.get()).map(read).toList();
  }

  (JoinedSelectStatement<HasResultSet, dynamic>, ShelfEntry Function(TypedResult)) _shelfQuery() {
    final unread = chapters.idx.count(
      filter: chapters.idx.isBiggerThan(books.durChapterIndex) & chapters.isVolume.equals(false),
    );
    final query = select(books).join([leftOuterJoin(chapters, chapters.bookUrl.equalsExp(books.bookUrl), useColumns: false)])
      ..where(books.inShelf.equals(true))
      ..addColumns([unread])
      ..groupBy([books.bookUrl])
      ..orderBy([
        OrderingTerm(expression: books.lastReadAt.isNull()),
        OrderingTerm.desc(books.lastReadAt),
        OrderingTerm.desc(books.addedAt),
      ]);
    return (query, (row) => (book: row.readTable(books), unread: row.read(unread) ?? 0));
  }

  Future<ShelfBook?> getBook(String bookUrl) => (select(books)..where((b) => b.bookUrl.equals(bookUrl))).getSingleOrNull();

  Stream<ShelfBook?> watchBook(String bookUrl) =>
      (select(books)..where((b) => b.bookUrl.equals(bookUrl))).watchSingleOrNull();

  /// 保存浏览中的书和它的目录（详情页加载完成时）。书已经存在时只更新书籍信息和目录，进度和是否在书架不变。
  Future<void> saveBrowsingBook(ShelfBook book, List<TocChapter> toc) => transaction(() async {
    await into(books).insert(
      book.copyWith(inShelf: false),
      onConflict: DoUpdate(
        (_) => BooksCompanion(
          origin: Value(book.origin),
          originName: Value(book.originName),
          name: Value(book.name),
          author: Value(book.author),
          kind: Value(book.kind),
          coverUrl: Value(book.coverUrl),
          intro: Value(book.intro),
          wordCount: Value(book.wordCount),
          latestChapterTitle: Value(book.latestChapterTitle),
          sourceData: Value(book.sourceData),
        ),
      ),
    );
    await _replaceToc(book.bookUrl, toc);
  });

  /// 书架更新目录：替换目录、更新最新章节和书源数据，按新目录重新定位的当前章节一并写入。
  Future<void> replaceToc(
    String bookUrl,
    List<TocChapter> toc, {
    required String? latestChapterTitle,
    required String sourceData,
    required ({int index, String? title}) current,
  }) => transaction(() async {
    await (update(books)..where((b) => b.bookUrl.equals(bookUrl))).write(
      BooksCompanion(
        latestChapterTitle: Value(latestChapterTitle),
        sourceData: Value(sourceData),
        durChapterIndex: Value(current.index),
        durChapterTitle: Value(current.title),
      ),
    );
    await _replaceToc(bookUrl, toc);
  });

  Future<void> _replaceToc(String bookUrl, List<TocChapter> toc) async {
    await (delete(chapters)..where((c) => c.bookUrl.equals(bookUrl))).go();
    await batch((b) => b.insertAll(chapters, toc));
  }

  Future<void> addToShelf(String bookUrl, DateTime now) => (update(books)..where((b) => b.bookUrl.equals(bookUrl))).write(
    BooksCompanion(inShelf: const Value(true), addedAt: Value(now)),
  );

  /// 移出书架：删除书籍、目录、正文缓存和进度。
  Future<void> removeBook(String bookUrl) => transaction(() async {
    await (delete(contents)..where((c) => c.bookUrl.equals(bookUrl))).go();
    await (delete(chapters)..where((c) => c.bookUrl.equals(bookUrl))).go();
    await (delete(books)..where((b) => b.bookUrl.equals(bookUrl))).go();
  });

  /// 换书源（app-storage「换书源时的数据」）：删除旧书的书籍、目录和正文缓存，写入书架上的新书和它的目录。
  /// 新地址上浏览中的那一行被覆盖，它的正文缓存保留：键是新书和新章节的地址，和新目录对得上。
  Future<void> changeSource(String oldBookUrl, ShelfBook book, List<TocChapter> toc) => transaction(() async {
    await removeBook(oldBookUrl);
    await into(books).insert(book, mode: InsertMode.insertOrReplace);
    await _replaceToc(book.bookUrl, toc);
  });

  /// 启动时清理浏览中的书（不在书架上的书重启后不保留）。
  Future<void> purgeBrowsingBooks() => transaction(() async {
    final browsing = selectOnly(books)
      ..addColumns([books.bookUrl])
      ..where(books.inShelf.equals(false));
    await (delete(contents)..where((c) => c.bookUrl.isInQuery(browsing))).go();
    await (delete(chapters)..where((c) => c.bookUrl.isInQuery(browsing))).go();
    await (delete(books)..where((b) => b.inShelf.equals(false))).go();
  });

  Future<void> saveProgress(String bookUrl, {required int index, required String url, required String title, required int position, required DateTime now}) =>
      (update(books)..where((b) => b.bookUrl.equals(bookUrl))).write(
        BooksCompanion(
          durChapterIndex: Value(index),
          durChapterUrl: Value(url),
          durChapterTitle: Value(title),
          durChapterPos: Value(position),
          lastReadAt: Value(now),
        ),
      );

  Future<List<TocChapter>> chaptersOf(String bookUrl) => _chaptersOf(bookUrl).get();

  Stream<List<TocChapter>> watchChapters(String bookUrl) => _chaptersOf(bookUrl).watch();

  SimpleSelectStatement<$ChaptersTable, TocChapter> _chaptersOf(String bookUrl) =>
      select(chapters)..where((c) => c.bookUrl.equals(bookUrl))..orderBy([(c) => OrderingTerm(expression: c.idx)]);

  // ---------------------------------------------------------------- 正文

  Future<ContentRow?> getContent(String bookUrl, String chapterUrl) =>
      (select(contents)..where((c) => c.bookUrl.equals(bookUrl) & c.chapterUrl.equals(chapterUrl))).getSingleOrNull();

  Future<void> putContent(ContentRow row) => into(contents).insertOnConflictUpdate(row);

  /// 正文缓存的大小：清除时会删掉的那些正文（add-settings 设计 D1）。
  Future<ContentCacheStats> contentCacheStats() async {
    final chapters = countAll();
    final bytes = const CustomExpression<int>('COALESCE(SUM(octet_length(content)), 0)');
    final row = await (selectOnly(contents)..addColumns([chapters, bytes])).getSingle();
    return (chapters: row.read(chapters)!, bytes: row.read(bytes)!);
  }

  /// 清除所有书的正文缓存，再 VACUUM 回收磁盘空间（设计 D2）。VACUUM 不能在事务里执行；
  /// 它失败（比如磁盘空间不足）时删除已经生效，只是文件没有变小，所以只记日志。
  Future<void> clearContents() async {
    await delete(contents).go();
    try {
      await customStatement('VACUUM');
    } catch (e) {
      log('清除正文缓存后 VACUUM 失败', error: e, name: 'storage');
    }
  }

  // ---------------------------------------------------------------- 书源级状态、Cookie、设置

  /// 未过期的书源级状态；过期的行顺手删除。
  Future<List<SourceKvRow>> loadSourceKv(DateTime now) => transaction(() async {
    await (delete(sourceKv)..where((r) => r.deadline.isSmallerOrEqualValue(now))).go();
    return select(sourceKv).get();
  });

  Future<void> putSourceKv(String key, String value, DateTime? deadline) =>
      into(sourceKv).insertOnConflictUpdate(SourceKvRow(key: key, value: value, deadline: deadline));

  Future<void> deleteSourceKv(String key) => (delete(sourceKv)..where((r) => r.key.equals(key))).go();

  Future<Map<String, String>> loadCookies() async => {for (final row in await select(cookies).get()) row.domain: row.cookie};

  /// [cookie] 为 null 时删除。
  Future<void> putCookie(String domain, String? cookie) => cookie == null
      ? (delete(cookies)..where((r) => r.domain.equals(domain))).go()
      : into(cookies).insertOnConflictUpdate(CookieRow(domain: domain, cookie: cookie));

  Future<Map<String, String>> loadSettings() async => {for (final row in await select(settings).get()) row.key: row.value};

  Future<void> putSetting(String key, String value) => into(settings).insertOnConflictUpdate(SettingRow(key: key, value: value));
}
