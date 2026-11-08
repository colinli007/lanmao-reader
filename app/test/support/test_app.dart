import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lanmao_reader/library/providers.dart';
import 'package:lanmao_reader/online/batch.dart';
import 'package:lanmao_reader/online/book_mapping.dart';
import 'package:lanmao_reader/online/online_content_source.dart';
import 'package:lanmao_reader/online/providers.dart';
import 'package:lanmao_reader/online/replace_rule_repository.dart';
import 'package:lanmao_reader/online/source_engine.dart';
import 'package:lanmao_reader/online/source_log.dart';
import 'package:lanmao_reader/online/source_repository.dart';
import 'package:lanmao_reader/reader/screen_awake.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:lanmao_reader/ui/theme.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/rule_engine.dart' as rule_engine show loadReplaceRules, replaceRuleError;

/// 假的链路执行方：按书源地址给出结果，记录调用次数。
final class FakeEngine implements SourceEngine {
  Future<List<SearchBook>> Function(BookSource source, String key)? onSearch;
  Future<Book> Function(BookSource source, Book book)? onBookInfo;
  Future<TocResult> Function(BookSource source, Book book)? onChapterList;
  Future<ChapterContent> Function(BookSource source, Book book, BookChapter chapter, String? next)? onContent;
  Future<Uint8List> Function(BookSource source, Book book, String src)? onImage;
  Future<List<ExploreKind>> Function(BookSource source)? onExploreKinds;
  Future<List<SearchBook>> Function(BookSource source, String url, int page)? onExplore;

  /// 不为空时代替正则替换规则的执行（注入超时等），否则在当前 isolate 里执行规则。
  Future<String> Function(String input, ReplaceRule rule)? onReplace;

  final List<String> calls = [];

  /// 每次批量调用收到的批次。
  final List<Batch> batches = [];

  @override
  Future<List<SearchBook>> search(BookSource source, String key, Batch batch) {
    calls.add('search ${source.bookSourceUrl}');
    batches.add(batch);
    return onSearch!(source, key);
  }

  @override
  Future<Book> bookInfo(BookSource source, Book book, {Batch? batch}) {
    calls.add('info ${book.bookUrl}');
    if (batch != null) batches.add(batch);
    return onBookInfo!(source, book);
  }

  @override
  Future<TocResult> chapterList(BookSource source, Book book, {Batch? batch}) {
    calls.add('toc ${book.bookUrl}');
    if (batch != null) batches.add(batch);
    return onChapterList!(source, book);
  }

  @override
  Future<ChapterContent> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl, Batch? batch}) {
    calls.add('content ${chapter.url}');
    if (batch != null) batches.add(batch);
    return onContent!(source, book, chapter, nextChapterUrl);
  }

  @override
  Future<Uint8List> image(BookSource source, Book book, String src) {
    calls.add('image $src');
    return onImage!(source, book, src);
  }

  @override
  Future<List<ExploreKind>> exploreKinds(BookSource source) {
    calls.add('kinds ${source.bookSourceUrl}');
    return onExploreKinds!(source);
  }

  @override
  Future<List<SearchBook>> explore(BookSource source, String url, int page) {
    calls.add('explore $url $page');
    return onExplore!(source, url, page);
  }

  @override
  Future<String> replace(String input, ReplaceRule rule) async {
    calls.add('replace ${rule.pattern}');
    return onReplace?.call(input, rule) ?? applyReplaceRule(_LocalEnvironment.instance, input, rule.pattern, rule.replacement);
  }

  @override
  Future<ReplaceRuleLoadResult> loadReplaceRules(String text) async => rule_engine.loadReplaceRules(text);

  @override
  Future<String?> replaceRuleError(String pattern, {required bool isRegex}) async =>
      rule_engine.replaceRuleError(pattern, isRegex: isRegex);
}

/// 在测试的 isolate 里执行正则用的环境：只提供不会被设置的中止标志，正则规则用不到其它能力。
final class _LocalEnvironment implements RuleEnvironment {
  _LocalEnvironment._();

  static final instance = _LocalEnvironment._();

  @override
  final Pointer<Int32> abortSignal = calloc<Int32>();

  @override
  void checkCancelled() {}

  @override
  HttpResult fetch(HttpRequest request) => throw UnsupportedError('fetch');

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => throw UnsupportedError('fetchAll');

  @override
  Object? store(StoreRequest request) => throw UnsupportedError('store');

  @override
  void log(SourceLog log) => throw UnsupportedError('log');
}

/// 记录屏幕常亮的调用，不交给平台。
final class FakeScreenAwake extends ScreenAwake {
  final List<bool> calls = [];

  @override
  void apply(bool on) => calls.add(on);
}

/// app 的全部依赖：内存数据库、假的链路执行方、假的屏幕常亮，其余和正式启动一样。
final class TestServices {
  TestServices._(this.db, this.repository, this.replaceRules, this.log, this.engine);

  final AppDatabase db;
  final SourceRepository repository;
  final ReplaceRuleRepository replaceRules;
  final SourceLogBuffer log;
  final FakeEngine engine;
  final FakeScreenAwake screen = FakeScreenAwake();
  late final OnlineContentSource contentSource = OnlineContentSource(engine, repository, replaceRules, cacheRetryDelay: Duration.zero);

  /// [file] 不为空时用文件数据库（关闭后重新 create 模拟重启），否则用内存数据库。
  static Future<TestServices> create({File? file}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // 关闭流时同步清理：否则 drift 在取消订阅时排一个零延时的定时器，widget 测试结束时会被当成泄漏
    final executor = file == null ? NativeDatabase.memory() : NativeDatabase(file);
    final db = AppDatabase(DatabaseConnection(executor, closeStreamsSynchronously: true));
    return TestServices._(db, await SourceRepository.load(db), await ReplaceRuleRepository.load(db), SourceLogBuffer(), FakeEngine());
  }

  List<Override> get overrides => [
    databaseProvider.overrideWithValue(db),
    contentSourceProvider.overrideWithValue(contentSource),
    sourceEngineProvider.overrideWithValue(engine),
    sourceRepositoryProvider.overrideWith((ref) => repository),
    replaceRuleRepositoryProvider.overrideWith((ref) => replaceRules),
    sourceLogProvider.overrideWith((ref) => log),
    screenAwakeProvider.overrideWithValue(screen),
  ];

  Widget app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
    overrides: [...this.overrides, ...overrides],
    child: MaterialApp(theme: appTheme(Brightness.light), darkTheme: appTheme(Brightness.dark), home: home),
  );

  /// 导入书源：[sources] 是书源 JSON 对象。
  Future<void> addSources(List<Map<String, Object?>> sources) => repository.import(loadBookSources(jsonEncode(sources)).sources);

  /// 导入替换规则：[rules] 是规则 JSON 对象。
  Future<void> addReplaceRules(List<Map<String, Object?>> rules) =>
      replaceRules.import(loadReplaceRules(jsonEncode(rules)).rules);
}

/// 一个简单的书源和它上面的一本书：[chapters] 章，第 i 章的正文是「第 i 章正文」加若干段。
extension SimpleBook on TestServices {
  static const sourceUrl = 'https://a.com';
  static const bookUrl = 'https://a.com/book/1';

  Future<void> useSimpleBook({int chapters = 5, int paragraphs = 3, String name = '三体', String author = '刘慈欣'}) async {
    await addSources([{'bookSourceUrl': sourceUrl, 'bookSourceName': '书源甲', 'searchUrl': '/s'}]);
    engine
      ..onSearch = ((source, key) async => [
        SearchBook(bookUrl: bookUrl, origin: sourceUrl, originName: '书源甲')
          ..name = name
          ..author = author,
      ])
      ..onBookInfo = ((source, book) async => book
        ..intro = '简介'
        ..tocUrl = '$bookUrl/toc')
      ..onChapterList = ((source, book) async => (
        book: book,
        chapters: [
          for (var i = 0; i < chapters; i++)
            BookChapter(bookUrl: book.bookUrl, baseUrl: '$bookUrl/toc')
              ..index = i
              ..title = '第$i章'
              ..url = '/$i.html',
        ],
      ))
      ..onContent = ((source, book, chapter, next) async =>
          ChapterContent([for (var p = 0; p < paragraphs; p++) '${chapter.title}第$p段'].join('\n'), title: chapter.title));
  }

  /// 直接把这本书放上书架（不经过界面）。[url]、[name] 用来放多本不同的书。
  Future<void> shelveSimpleBook({int chapters = 5, String url = bookUrl, String name = '三体'}) async {
    final toc = await engine.onChapterList!(repository[SimpleBook.sourceUrl]!.source, Book(bookUrl: url, origin: sourceUrl, originName: '书源甲'));
    await db.saveBrowsingBook(
      ShelfBook(
        bookUrl: url,
        origin: sourceUrl,
        originName: '书源甲',
        name: name,
        author: '刘慈欣',
        latestChapterTitle: toc.chapters.last.title,
        durChapterIndex: 0,
        durChapterPos: 0,
        inShelf: false,
        sourceData: bookData(toc.book),
      ),
      [for (final chapter in toc.chapters) tocChapterOf(chapter)],
    );
    await db.addToShelf(url, DateTime(2026));
    engine.calls.clear();
  }
}
