/// 四条链路：搜索、详情、目录、正文。照 MD3 的 `WebBook`、`BookList`、`BookInfo`、`BookChapterList`、`BookContent` 移植。
///
/// 同步执行，网络和取消来自 [RuleEnvironment]：worker 里用阻塞桥，测试里用回放环境。每次请求之前、每处理一项之后检查取消。
/// 出错时错误上带着书源名和出错的字段。可选字段（分类、字数、简介等）的规则错误和 MD3 一样被吞掉，
/// 但需要 JS、WebView 的错误不吞：MD3 里这些规则能正常执行，跳过会得到不同的结果。
library;

import 'dart:typed_data';

import '../core/environment.dart';
import '../core/errors.dart';
import '../core/source_task.dart';
import '../js/host_api.dart' show jsBytes;
import '../js/source_js.dart';
import '../net/java_url.dart';
import '../regex/source_regex.dart';
import '../request/analyze_url.dart';
import '../request/str_response.dart';
import '../rule/analyze_rule.dart';
import '../rule/rule_data.dart';
import '../source/book_source.dart';
import '../text/html_unescape.dart';
import 'explore_kind.dart';
import 'formatter.dart';
import 'models.dart';

// ---------------------------------------------------------------- 搜索

/// 搜索：请求搜索地址，解析结果列表。搜索响应本身就是详情页时，返回一个结果并保存这个页面。
List<SearchBook> searchBooks(RuleEnvironment env, BookSource source, String key, {int page = 1}) {
  final step = prepareSearch(env, source, key, page: page);
  env.checkCancelled();
  return finishSearch(step, env.fetch(step.http));
}

/// 分段搜索的第一段结果：构造好的请求，以及第二段要用的请求上下文和本次链路的变量。
/// 都是普通 Dart 对象，可以在 isolate 之间传递，第二段可以在另一个 worker 上执行。
final class SearchStep {
  SearchStep._(this._request, this._ruleData);

  final SourceRequest _request;
  final ChainData _ruleData;

  /// 交给提交方发出的请求。
  HttpRequest get http => _request.http;
}

/// 分段搜索的第一段：构造搜索请求（地址里的 JS、请求头的 JS），请求由提交方发出，响应交给 [finishSearch]。
/// 网络等待因此不占 worker；两段连着执行就是 [searchBooks]。
SearchStep prepareSearch(RuleEnvironment env, BookSource source, String key, {int page = 1}) {
  return _withTask(env, source, 'searchUrl', (task) {
    final searchUrl = task.source.searchUrl;
    if (searchUrl == null || searchUrl.trim().isEmpty) throw RuleException('搜索url不能为空');
    final ruleData = ChainData();
    final request = buildSourceRequest(
      task,
      searchUrl,
      key: key,
      page: page,
      baseUrl: task.source.bookSourceUrl,
      ruleData: ruleData,
    );
    // 这一段的 JS 作用域已经全部释放，登记的对象随之失效（见 [HandleTable.clear]）
    task.handles.clear();
    return SearchStep._(request, ruleData);
  });
}

/// 分段搜索的第二段：处理响应（选项 `type`、`bodyJs`，再执行 `loginCheckJs`），解析结果列表。
List<SearchBook> finishSearch(SearchStep step, HttpResult result) {
  final request = step._request;
  return _inTask(request.task, 'searchUrl', (task) {
    final response = _toResponse(_loginCheck(task, request, request.response(result)));
    return _analyzeBookList(task, step._ruleData, request, response);
  });
}

/// 书籍列表（MD3 的 `BookList.analyzeBookList`）。[explore] 是发现：不判断 `bookUrlPattern`，
/// 规则用 `ruleExplore`，它的 `bookList` 为空时用 `ruleSearch`。
List<SearchBook> _analyzeBookList(
  SourceTask task,
  ChainData ruleData,
  SourceRequest request,
  _Response response, {
  bool explore = false,
}) {
  final baseUrl = response.url;
  final body = response.body;
  final source = task.source;
  final rules = explore && (source.ruleExplore['bookList']?.trim().isNotEmpty ?? false) ? source.ruleExplore : source.ruleSearch;
  final analyzeRule = AnalyzeRule(task, ruleData: ruleData)
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(baseUrl);

  final pattern = source.bookUrlPattern;
  if (pattern != null && !explore) {
    final regex = task.inField('bookUrlPattern', () => SourceRegex.tryCompile(pattern) ?? (throw RuleException('正则无法编译：$pattern')));
    if (regex.matchesEntire(task.env, baseUrl)) {
      final item = _infoItem(task, analyzeRule, request, body, baseUrl, ruleData, response.redirected);
      return [?item?..infoHtml = body];
    }
  }

  var listRule = rules['bookList'] ?? '';
  var reverse = false;
  if (listRule.startsWith('-')) {
    reverse = true;
    listRule = listRule.substring(1);
  }
  if (listRule.startsWith('+')) listRule = listRule.substring(1);
  final collections = task.inField(rules.field('bookList'), () => analyzeRule.getElements(listRule));
  task.env.checkCancelled();

  if (collections.isEmpty && (pattern == null || pattern.isEmpty)) {
    final item = _infoItem(task, analyzeRule, request, body, baseUrl, ruleData, response.redirected);
    return [?item?..infoHtml = body];
  }

  // 字段规则在 setContent(item) 之前拆好，取值语法由整页内容决定
  final ruleName = analyzeRule.prepare(rules['name']);
  final ruleBookUrl = analyzeRule.prepare(rules['bookUrl']);
  final ruleAuthor = analyzeRule.prepare(rules['author']);
  final ruleCoverUrl = analyzeRule.prepare(rules['coverUrl']);
  final ruleIntro = analyzeRule.prepare(rules['intro']);
  final ruleKind = analyzeRule.prepare(rules['kind']);
  final ruleLastChapter = analyzeRule.prepare(rules['lastChapter']);
  final ruleWordCount = analyzeRule.prepare(rules['wordCount']);

  final books = <SearchBook>[];
  final seen = <String>{};
  for (final item in collections) {
    task.env.checkCancelled();
    final book = SearchBook(
      bookUrl: '',
      origin: task.source.bookSourceUrl,
      originName: task.source.bookSourceName,
      variables: ruleData.variables,
    );
    analyzeRule
      ..ruleData = book
      ..setContent(item);
    book.name = formatBookName(task.inField(rules.field('name'), () => analyzeRule.getStringOf(ruleName)));
    if (book.name.isEmpty) continue;
    book.author = formatBookAuthor(task.inField(rules.field('author'), () => analyzeRule.getStringOf(ruleAuthor)));
    _optional(task, rules.field('kind'), () {
      final kind = analyzeRule.getStringListOf(ruleKind)?.join(',');
      book.kind = kind == null ? null : _take(kind, 1000);
    });
    _optional(task, rules.field('wordCount'), () => book.wordCount = wordCountFormat(analyzeRule.getStringOf(ruleWordCount)));
    _optional(task, rules.field('lastChapter'), () => book.latestChapterTitle = analyzeRule.getStringOf(ruleLastChapter));
    _optional(task, rules.field('intro'), () => book.intro = _take(formatHtml(analyzeRule.getStringOf(ruleIntro)), 5000));
    _optional(task, rules.field('coverUrl'), () {
      final cover = analyzeRule.getStringOf(ruleCoverUrl);
      if (cover.isNotEmpty) book.coverUrl = absoluteUrlFrom(baseUrl, cover);
    });
    book.bookUrl = task.inField(rules.field('bookUrl'), () => analyzeRule.getStringOf(ruleBookUrl, isUrl: true));
    if (book.bookUrl.isEmpty) book.bookUrl = baseUrl;
    if (baseUrl == book.bookUrl) book.infoHtml = body;
    // 按书籍地址去重，保留第一次出现的
    if (seen.add(book.bookUrl)) books.add(book);
  }
  return reverse ? books.reversed.toList() : books;
}

/// 搜索页当作详情页解析：书籍地址是最终地址（发生过重定向时）或搜索地址（带着选项）。书名为空时没有结果。
SearchBook? _infoItem(
  SourceTask task,
  AnalyzeRule analyzeRule,
  SourceRequest request,
  String body,
  String baseUrl,
  ChainData ruleData,
  bool redirected,
) {
  final book = Book(
    bookUrl: redirected ? baseUrl : absoluteUrlFrom(request.url, request.ruleUrl),
    origin: task.source.bookSourceUrl,
    originName: task.source.bookSourceName,
    variables: ruleData.variables,
  );
  analyzeRule.ruleData = book;
  _analyzeBookInfo(task, book, body, analyzeRule, baseUrl: baseUrl, redirectUrl: baseUrl, canReName: false);
  if (book.name.trim().isEmpty) return null;
  return SearchBook(bookUrl: book.bookUrl, origin: book.origin, originName: book.originName, variables: book.variables)
    ..name = book.name
    ..author = book.author
    ..kind = book.kind
    ..coverUrl = book.coverUrl
    ..intro = book.intro
    ..wordCount = book.wordCount
    ..latestChapterTitle = book.latestChapterTitle;
}

// ---------------------------------------------------------------- 发现

/// 发现分类（MD3 的 `BookSource.exploreKinds`）：`exploreUrl` 以 `<js>`、`@js:` 开头时先用书源级的 JS 上下文执行，
/// 再按 [parseExploreKinds] 解析。没有发现地址时没有分类；JS 出错、JSON 不合法时抛出错误。
List<ExploreKind> getExploreKinds(RuleEnvironment env, BookSource source) {
  final exploreUrl = source.exploreUrl;
  if (exploreUrl == null || exploreUrl.trim().isEmpty) return const [];
  return _withTask(env, source, 'exploreUrl', (task) {
    final lower = exploreUrl.toLowerCase();
    final text = lower.startsWith('@js:')
        ? _jsText(SourceJs.instance.evalSource(task, exploreUrl.substring(4)))
        : lower.startsWith('<js>')
        ? _jsText(SourceJs.instance.evalSource(task, exploreUrl.substring(4, exploreUrl.lastIndexOf('<'))))
        : exploreUrl;
    try {
      return parseExploreKinds(text);
    } on FormatException catch (e) {
      throw RuleException('发现地址不是合法的 JSON：${e.message}');
    }
  });
}

/// Kotlin 的 `toString()`：null 是 `null`。
String _jsText(Object? value) => value == null ? 'null' : valueToString(value);

/// 发现（MD3 的 `WebBook.exploreBook`）：请求分类地址的第 [page] 页，执行 `loginCheckJs`，按发现模式解析书籍列表。
List<SearchBook> exploreBooks(RuleEnvironment env, BookSource source, String url, {int page = 1}) {
  return _withTask(env, source, 'exploreUrl', (task) {
    final ruleData = ChainData();
    final request = buildSourceRequest(task, url, page: page, baseUrl: task.source.bookSourceUrl, ruleData: ruleData);
    return _analyzeBookList(task, ruleData, request, _fetch(task, request, loginCheck: true), explore: true);
  });
}

// ---------------------------------------------------------------- 详情

/// 详情：已有保存的详情页时直接解析，否则请求书籍地址。目录地址等于书籍地址时保存详情页给目录链路。
Book getBookInfo(RuleEnvironment env, BookSource source, Book book, {bool canReName = true}) {
  return _withTask(env, source, 'bookUrl', (task) {
    final infoHtml = book.infoHtml;
    if (infoHtml != null && infoHtml.isNotEmpty) {
      final analyzeRule = AnalyzeRule(task, ruleData: book)
        ..setContent(infoHtml, baseUrl: book.bookUrl)
        ..setRedirectUrl(book.bookUrl);
      _analyzeBookInfo(task, book, infoHtml, analyzeRule, baseUrl: book.bookUrl, redirectUrl: book.bookUrl, canReName: canReName);
      return book;
    }
    final request = buildSourceRequest(task, book.bookUrl, baseUrl: task.source.bookSourceUrl, ruleData: book);
    final response = _fetch(task, request, loginCheck: true);
    final analyzeRule = AnalyzeRule(task, ruleData: book)
      ..setContent(response.body, baseUrl: book.bookUrl)
      ..setRedirectUrl(response.url);
    _analyzeBookInfo(task, book, response.body, analyzeRule, baseUrl: book.bookUrl, redirectUrl: response.url, canReName: canReName);
    return book;
  });
}

void _analyzeBookInfo(
  SourceTask task,
  Book book,
  String body,
  AnalyzeRule analyzeRule, {
  required String baseUrl,
  required String redirectUrl,
  required bool canReName,
}) {
  final rules = task.source.ruleBookInfo;
  final init = rules['init'];
  if (init != null && init.trim().isNotEmpty) {
    task.env.checkCancelled();
    final element = task.inField(rules.field('init'), () => analyzeRule.getElement(init));
    // MD3 在这里 setContent(null) 抛 AssertionError（D12）
    if (element == null) throw RuleException('详情 init 取不到', field: rules.field('init'));
    analyzeRule.setContent(element);
  }
  final mCanReName = canReName && (rules['canReName']?.trim().isNotEmpty ?? false);
  task.env.checkCancelled();
  final name = formatBookName(task.inField(rules.field('name'), () => analyzeRule.getString(rules['name'])));
  if (name.isNotEmpty && (mCanReName || book.name.isEmpty)) book.name = name;
  final author = formatBookAuthor(task.inField(rules.field('author'), () => analyzeRule.getString(rules['author'])));
  if (author.isNotEmpty && (mCanReName || book.author.isEmpty)) book.author = author;
  _optional(task, rules.field('kind'), () {
    final kind = analyzeRule.getStringList(rules['kind'])?.join(',');
    if (kind != null && kind.isNotEmpty) book.kind = _take(kind, 1000);
  });
  _optional(task, rules.field('wordCount'), () {
    final wordCount = wordCountFormat(analyzeRule.getString(rules['wordCount']));
    if (wordCount.isNotEmpty) book.wordCount = wordCount;
  });
  _optional(task, rules.field('lastChapter'), () {
    final lastChapter = analyzeRule.getString(rules['lastChapter']);
    if (lastChapter.isNotEmpty) book.latestChapterTitle = lastChapter;
  });
  _optional(task, rules.field('intro'), () {
    final intro = analyzeRule.getString(rules['intro']).trimLeft();
    if (intro.startsWith('<usehtml>') || intro.startsWith('<md>') || intro.startsWith('<useweb>')) {
      book.intro = intro;
    } else {
      final formatted = _take(formatHtml(intro), 5000);
      if (formatted.isNotEmpty) book.intro = formatted;
    }
  });
  _optional(task, rules.field('coverUrl'), () {
    final cover = analyzeRule.getString(rules['coverUrl']);
    if (cover.isNotEmpty) book.coverUrl = absoluteUrlFrom(redirectUrl, cover);
  });
  task.env.checkCancelled();
  if (task.source.bookSourceType != BookSourceType.file) {
    book.tocUrl = task.inField(rules.field('tocUrl'), () => analyzeRule.getString(rules['tocUrl'], isUrl: true));
    if (book.tocUrl.isEmpty) book.tocUrl = baseUrl;
    if (book.tocUrl == baseUrl) book.tocHtml = body;
  } else {
    book.downloadUrls = task.inField(rules.field('downloadUrls'), () => analyzeRule.getStringList(rules['downloadUrls'], isUrl: true));
    if (book.downloadUrls == null || book.downloadUrls!.isEmpty) {
      throw RuleException('下载链接为空', field: rules.field('downloadUrls'));
    }
  }
}

// ---------------------------------------------------------------- 目录

/// 目录：目录就在详情页时直接解析保存的页面，否则请求目录地址。支持串行和并发两种多页目录。
List<BookChapter> getChapterList(RuleEnvironment env, BookSource source, Book book) {
  return _withTask(env, source, 'tocUrl', (task) {
    final tocHtml = book.tocHtml;
    if (book.bookUrl == book.tocUrl && tocHtml != null && tocHtml.isNotEmpty) {
      return _analyzeChapterList(task, book, baseUrl: book.tocUrl, redirectUrl: book.tocUrl, body: tocHtml);
    }
    final request = buildSourceRequest(task, book.tocUrl, baseUrl: book.bookUrl, ruleData: book);
    final response = _fetch(task, request, loginCheck: true);
    return _analyzeChapterList(task, book, baseUrl: book.tocUrl, redirectUrl: response.url, body: response.body);
  });
}

List<BookChapter> _analyzeChapterList(
  SourceTask task,
  Book book, {
  required String baseUrl,
  required String redirectUrl,
  required String body,
}) {
  final rules = task.source.ruleToc;
  var listRule = rules['chapterList'] ?? '';
  var reverse = false;
  if (listRule.startsWith('-')) {
    reverse = true;
    listRule = listRule.substring(1);
  }
  if (listRule.startsWith('+')) listRule = listRule.substring(1);

  final chapters = <BookChapter>[];
  final visited = <String>[redirectUrl];
  var page = _tocPage(task, book, baseUrl, redirectUrl, body, listRule, getNextUrl: true);
  chapters.addAll(page.chapters);
  if (page.nextUrls.length == 1) {
    // 只有一个下一页：串行翻页，访问过的不再访问
    var nextUrl = page.nextUrls.single;
    while (nextUrl.isNotEmpty && !visited.contains(nextUrl)) {
      visited.add(nextUrl);
      final response = _fetch(task, buildSourceRequest(task, nextUrl, ruleData: book));
      page = _tocPage(task, book, nextUrl, nextUrl, response.body, listRule, getNextUrl: true);
      nextUrl = page.nextUrls.firstOrNull ?? '';
      chapters.addAll(page.chapters);
    }
  } else if (page.nextUrls.length > 1) {
    // 首页列出了全部分页：并发请求这一批，子页不再找下一页
    final requests = [for (final url in page.nextUrls) buildSourceRequest(task, url, ruleData: book)];
    final responses = _fetchAll(task, requests);
    for (final (index, response) in responses.indexed) {
      final pageData = _tocPage(task, book, page.nextUrls[index], response.url, response.body, listRule, getNextUrl: false);
      chapters.addAll(pageData.chapters);
    }
  }
  if (chapters.isEmpty) throw RuleException(RuleException.tocEmpty, field: rules.field('chapterList'));

  // 没有 - 时：倒过来去重再倒回来，重复的保留最后一次；有 - 时：去重后整体倒序。
  // 书籍设置了目录倒序（JS 的 book.setReverseToc）时不再倒回来
  var list = reverse ? chapters : chapters.reversed.toList();
  final seen = <String>{};
  list = [
    for (final chapter in list)
      if (seen.add(chapter.url)) chapter,
  ];
  if (!book.reverseToc) list = list.reversed.toList();
  for (final (index, chapter) in list.indexed) {
    chapter.index = index;
  }
  final formatJs = rules['formatJs'];
  if (formatJs != null && formatJs.trim().isNotEmpty) {
    task.inField(rules.field('formatJs'), () => SourceJs.instance.formatChapterTitles(task, formatJs, list));
  }
  book
    ..durChapterTitle = (book.durChapterIndex < list.length ? list[book.durChapterIndex] : list.last).title
    ..totalChapterNum = list.length;
  return list;
}

typedef _TocPage = ({List<BookChapter> chapters, List<String> nextUrls});

_TocPage _tocPage(
  SourceTask task,
  Book book,
  String baseUrl,
  String redirectUrl,
  String body,
  String listRule, {
  required bool getNextUrl,
}) {
  final rules = task.source.ruleToc;
  final analyzeRule = AnalyzeRule(task, ruleData: book)
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(redirectUrl);
  final elements = task.inField(rules.field('chapterList'), () => analyzeRule.getElements(listRule));
  final nextUrls = <String>[];
  final nextRule = rules['nextTocUrl'];
  if (getNextUrl && nextRule != null && nextRule.isNotEmpty) {
    final urls = task.inField(rules.field('nextTocUrl'), () => analyzeRule.getStringList(nextRule, isUrl: true));
    for (final url in urls ?? const <String>[]) {
      if (url != redirectUrl) nextUrls.add(url);
    }
  }
  task.env.checkCancelled();
  final chapters = <BookChapter>[];
  if (elements.isEmpty) return (chapters: chapters, nextUrls: nextUrls);

  final nameRule = analyzeRule.prepare(rules['chapterName']);
  final urlRule = analyzeRule.prepare(rules['chapterUrl']);
  final vipRule = analyzeRule.prepare(rules['isVip']);
  final payRule = analyzeRule.prepare(rules['isPay']);
  final updateTimeRule = analyzeRule.prepare(rules['updateTime']);
  final volumeRule = analyzeRule.prepare(rules['isVolume']);
  for (final (index, item) in elements.indexed) {
    task.env.checkCancelled();
    analyzeRule.setContent(item);
    final chapter = BookChapter(bookUrl: book.bookUrl, baseUrl: redirectUrl);
    analyzeRule.chapter = chapter;
    chapter.title = task.inField(rules.field('chapterName'), () => analyzeRule.getStringOf(nameRule));
    chapter.url = task.inField(rules.field('chapterUrl'), () => analyzeRule.getStringOf(urlRule));
    chapter.tag = task.inField(rules.field('updateTime'), () => analyzeRule.getStringOf(updateTimeRule));
    chapter.isVolume = isTrue(task.inField(rules.field('isVolume'), () => analyzeRule.getStringOf(volumeRule)));
    if (chapter.url.isEmpty) chapter.url = chapter.isVolume ? '${chapter.title}$index' : baseUrl;
    if (chapter.title.isEmpty) continue;
    chapter.isVip = isTrue(task.inField(rules.field('isVip'), () => analyzeRule.getStringOf(vipRule)));
    chapter.isPay = isTrue(task.inField(rules.field('isPay'), () => analyzeRule.getStringOf(payRule)));
    chapters.add(chapter);
  }
  return (chapters: chapters, nextUrls: nextUrls);
}

// ---------------------------------------------------------------- 正文

/// 章节的绝对地址：相对章节所在的目录页拼接，保留 `,{选项}`；没有链接的卷返回目录页地址。
String chapterAbsoluteUrl(BookChapter chapter) {
  if (chapter.url.startsWith(chapter.title) && chapter.isVolume) return chapter.baseUrl;
  final match = _paramPattern.firstMatch(chapter.url);
  final before = match == null ? chapter.url : chapter.url.substring(0, match.start);
  final absolute = absoluteUrlFrom(chapter.baseUrl, before);
  return match == null ? absolute : '$absolute,${chapter.url.substring(match.end)}';
}

final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');
final RegExp _useHtml = RegExp('<usehtml>.*?</usehtml>', dotAll: true);
final RegExp _imgTitle = RegExp(r'(.*)((?:data|https?):[\s\S]+)$');

/// 正文：请求章节地址（目录就在详情页且章节地址就是书籍地址时用保存的页面），格式化成纯文本，按需翻页。
/// [nextChapterUrl] 是下一章的地址，用来在翻页时判断已经到了下一章（MD3 从数据库里取）。
ChapterContent getContent(
  RuleEnvironment env,
  BookSource source,
  Book book,
  BookChapter chapter, {
  String? nextChapterUrl,
}) {
  return _withTask(env, source, 'ruleContent.content', (task) {
    if (task.source.bookSourceType == BookSourceType.file) throw RuleException('不支持的书源类型');
    final rules = task.source.ruleContent;
    final contentRule = rules['content'];
    if (contentRule == null || contentRule.isEmpty) return ChapterContent(chapter.url, title: chapter.title);
    if (chapter.isVolume && chapter.url.startsWith(chapter.title)) {
      return ChapterContent(chapter.tag ?? '', title: chapter.title);
    }
    final absoluteUrl = chapterAbsoluteUrl(chapter);
    final tocHtml = book.tocHtml;
    if (chapter.url == book.bookUrl && tocHtml != null && tocHtml.isNotEmpty) {
      return _analyzeContent(task, book, chapter, baseUrl: absoluteUrl, redirectUrl: absoluteUrl, body: tocHtml, nextChapterUrl: nextChapterUrl);
    }
    final request = buildSourceRequest(task, absoluteUrl, baseUrl: book.tocUrl, ruleData: book, chapter: chapter);
    final response = _fetch(task, request, loginCheck: true);
    return _analyzeContent(task, book, chapter, baseUrl: absoluteUrl, redirectUrl: response.url, body: response.body, nextChapterUrl: nextChapterUrl);
  });
}

/// 正文里的一张图片（book-chains「正文图片」，add-content-images 设计 D9；MD3 `BookHelp.saveImage`）：
/// `data:` 地址直接解码（和请求共用 [dataUriBytes]），其余按书源构造请求取原始字节，非 2xx 报错；再执行 `ruleContent.imageDecode`。
Uint8List getContentImage(RuleEnvironment env, BookSource source, Book book, String src) {
  return _withTask(env, source, 'image', (task) {
    final bytes = src.startsWith('data:')
        ? dataUriBytes(src) ?? (throw RuleException('不支持的图片地址：${_take(src, 40)}'))
        : _imageResponseBytes(task, book, src);
    final decode = task.source.ruleContent['imageDecode'];
    if (decode == null || decode.trim().isEmpty) return bytes;
    return task.inField('ruleContent.imageDecode', () {
      final result = SourceJs.instance.evalImageDecode(task, decode, book: book, bytes: bytes, src: src);
      if (result == null) throw RuleException('图片解密的结果为空');
      return jsBytes(result);
    });
  });
}

Uint8List _imageResponseBytes(SourceTask task, Book book, String src) {
  final request = buildSourceRequest(task, src, ruleData: book);
  task.env.checkCancelled();
  final result = task.env.fetch(request.http);
  if (result.statusCode < 200 || result.statusCode >= 300) throw RuleException('图片请求失败：HTTP ${result.statusCode}');
  return result.body;
}

ChapterContent _analyzeContent(
  SourceTask task,
  Book book,
  BookChapter chapter, {
  required String baseUrl,
  required String redirectUrl,
  required String body,
  String? nextChapterUrl,
}) {
  final rules = task.source.ruleContent;
  final pages = <String>[];
  final visited = <String>[redirectUrl];
  final analyzeRule = AnalyzeRule(task, ruleData: book, chapter: chapter)
    ..nextChapterUrl = nextChapterUrl
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(redirectUrl);

  var page = _contentPage(task, book, chapter, baseUrl, redirectUrl, body, getNextUrl: true, nextChapterUrl: nextChapterUrl);
  pages.add(page.content);
  if (page.nextUrls.length == 1) {
    var nextUrl = page.nextUrls.single;
    while (nextUrl.isNotEmpty && !visited.contains(nextUrl)) {
      // 翻页前判断：这个地址已经是下一章了就停止
      if (nextChapterUrl != null &&
          nextChapterUrl.isNotEmpty &&
          absoluteUrlFrom(redirectUrl, nextUrl) == absoluteUrlFrom(redirectUrl, nextChapterUrl)) {
        break;
      }
      visited.add(nextUrl);
      final response = _fetch(task, buildSourceRequest(task, nextUrl, ruleData: book));
      page = _contentPage(task, book, chapter, nextUrl, response.url, response.body, getNextUrl: true, nextChapterUrl: nextChapterUrl);
      nextUrl = page.nextUrls.firstOrNull ?? '';
      pages.add(page.content);
    }
  } else if (page.nextUrls.length > 1) {
    final responses = _fetchAll(task, [for (final url in page.nextUrls) buildSourceRequest(task, url, ruleData: book)]);
    for (final (index, response) in responses.indexed) {
      pages.add(
        _contentPage(task, book, chapter, page.nextUrls[index], response.url, response.body, getNextUrl: false, nextChapterUrl: nextChapterUrl)
            .content,
      );
    }
  }

  final subRule = rules['subContent'];
  if (subRule != null && subRule.trim().isNotEmpty) {
    final raw = task.inField(rules.field('subContent'), () => analyzeRule.getString(subRule, unescape: false)).trim();
    final sub = raw.toLowerCase().startsWith('http') ? _fetch(task, buildSourceRequest(task, raw, ruleData: book)).body : raw;
    if (sub.trim().isNotEmpty && task.source.bookSourceType == BookSourceType.text) pages.add(sub);
  }
  var content = pages.join('\n');

  var title = chapter.title;
  String? reviewImg;
  final titleRule = rules['title'];
  if (titleRule != null && titleRule.trim().isNotEmpty) {
    String? found;
    try {
      found = task.inField(rules.field('title'), () => analyzeRule.getString(titleRule));
    } on RuleException {
      // MD3 用 runCatching 吞掉
    } on JsEvalException {
      // 同上
    }
    if (found != null && found.trim().isNotEmpty) {
      final match = _imgTitle.firstMatch(found);
      if (match != null) {
        found = match.group(1)!.isNotEmpty ? match.group(1)! : chapter.title;
        reviewImg = match.group(2);
      }
      title = found;
    }
  }

  final replaceRegex = rules['replaceRegex'];
  if (replaceRegex != null && replaceRegex.isNotEmpty) {
    content = content.split('\n').map((line) => line.trim()).join('\n');
    content = task.inField(rules.field('replaceRegex'), () => analyzeRule.getString(replaceRegex, content: content));
    content = content.split('\n').map((line) => '$paragraphIndent$line').join('\n');
  }
  if (!chapter.isVolume && content.trim().isEmpty) throw RuleException(RuleException.contentEmpty, field: rules.field('content'));
  return ChapterContent(content, title: title, reviewImg: reviewImg);
}

typedef _ContentPage = ({String content, List<String> nextUrls});

_ContentPage _contentPage(
  SourceTask task,
  Book book,
  BookChapter chapter,
  String baseUrl,
  String redirectUrl,
  String body, {
  required bool getNextUrl,
  String? nextChapterUrl,
}) {
  final rules = task.source.ruleContent;
  final analyzeRule = AnalyzeRule(task, ruleData: book, chapter: chapter)
    ..nextChapterUrl = nextChapterUrl
    ..setContent(body, baseUrl: baseUrl);
  final redirect = analyzeRule.setRedirectUrl(redirectUrl);
  var content = task.inField(rules.field('content'), () => analyzeRule.getString(rules['content'], unescape: false));
  if (task.source.bookSourceType != BookSourceType.audio && task.source.bookSourceType != BookSourceType.video) {
    // 先用占位符保护 <usehtml>…</usehtml>（MD3 的 adaptSpecialStyle 默认开启）
    final kept = <String, String>{};
    content = content.replaceAllMapped(_useHtml, (match) {
      final placeholder = '{usehtml_${kept.length}}';
      kept[placeholder] = match.group(0)!;
      return placeholder;
    });
    content = formatKeepImg(content, redirect);
    if (content.contains('&')) content = unescapeHtml4(content);
    for (final MapEntry(:key, :value) in kept.entries) {
      content = content.replaceAll(key, value);
    }
  }
  final nextUrls = <String>[];
  final nextRule = rules['nextContentUrl'];
  if (getNextUrl && nextRule != null && nextRule.isNotEmpty) {
    nextUrls.addAll(task.inField(rules.field('nextContentUrl'), () => analyzeRule.getStringList(nextRule, isUrl: true)) ?? const []);
  }
  task.env.checkCancelled();
  return (content: content, nextUrls: nextUrls);
}

// ---------------------------------------------------------------- 公共

typedef _Response = ({String url, String body, bool redirected});

/// 发出请求（请求之前检查取消），选项 `type`、`bodyJs` 在 [SourceRequest.fetch] 里处理。
/// [loginCheck] 时执行书源的 `loginCheckJs`：MD3 只对每条链路的第一个请求执行。
_Response _fetch(SourceTask task, SourceRequest request, {bool loginCheck = false}) {
  var response = request.fetch();
  if (loginCheck) response = _loginCheck(task, request, response);
  return _toResponse(response);
}

List<_Response> _fetchAll(SourceTask task, List<SourceRequest> requests) {
  task.env.checkCancelled();
  final results = task.env.fetchAll([for (final request in requests) request.http]);
  return [for (final (index, result) in results.indexed) _toResponse(requests[index].response(result))];
}

_Response _toResponse(StrResponse response) => (url: response.url, body: response.body ?? '', redirected: response.redirected);

/// `loginCheckJs`：`result` 是响应对象，`java` 是这次请求的 URL 上下文，返回的响应对象代替原响应。
StrResponse _loginCheck(SourceTask task, SourceRequest request, StrResponse response) {
  final js = task.source.loginCheckJs;
  if (js == null || js.trim().isEmpty) return response;
  return task.inField('loginCheckJs', () {
    final checked = SourceJs.instance.evalUrl(request, js, result: response);
    if (checked is! StrResponse) throw JsEvalException('loginCheckJs 的返回值不是响应对象');
    return checked;
  });
}

/// 可选字段：规则错误和 JS 错误吞掉（MD3 的 try/catch，只记日志），本引擎不支持的能力（JS 用法、WebView、宿主 API）照常抛出。
void _optional(SourceTask task, String field, void Function() body) {
  try {
    task.inField(field, body);
  } on RuleException {
    // 和 MD3 一样只记日志
  } on JsEvalException {
    // 同上
  } on FormatException {
    // 字数超出范围等
  }
}

/// 一次链路调用：建立任务的书源上下文，给链路里的错误补上书源名，没有字段时补上 [field]。
T _withTask<T>(RuleEnvironment env, BookSource source, String field, T Function(SourceTask task) body) =>
    _inTask(SourceTask(env, source), field, body);

/// 在已有的任务上继续执行（分段搜索的第二段），错误的处理同 [_withTask]。
T _inTask<T>(SourceTask task, String field, T Function(SourceTask task) body) {
  try {
    return body(task..field = field);
  } on RuleEngineException catch (e) {
    e.sourceName ??= task.source.bookSourceName;
    e.field ??= field;
    rethrow;
  }
}

/// Kotlin 的 `String.take(n)`。
String _take(String text, int n) => text.length <= n ? text : text.substring(0, n);
