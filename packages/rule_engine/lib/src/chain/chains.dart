/// 四条链路：搜索、详情、目录、正文。照 MD3 的 `WebBook`、`BookList`、`BookInfo`、`BookChapterList`、`BookContent` 移植。
///
/// 同步执行，网络和取消来自 [RuleEnvironment]：worker 里用阻塞桥，测试里用回放环境。每次请求之前、每处理一项之后检查取消。
/// 出错时错误上带着书源名和出错的字段。可选字段（分类、字数、简介等）的规则错误和 MD3 一样被吞掉，
/// 但需要 JS、WebView 的错误不吞：MD3 里这些规则能正常执行，跳过会得到不同的结果。
library;

import '../core/environment.dart';
import '../core/errors.dart';
import '../net/java_url.dart';
import '../regex/source_regex.dart';
import '../request/analyze_url.dart';
import '../request/response_decoder.dart';
import '../rule/analyze_rule.dart';
import '../rule/rule_data.dart';
import '../source/book_source.dart';
import '../text/html_unescape.dart';
import 'formatter.dart';
import 'models.dart';

// ---------------------------------------------------------------- 搜索

/// 搜索：请求搜索地址，解析结果列表。搜索响应本身就是详情页时，返回一个结果并保存这个页面。
List<SearchBook> searchBooks(RuleEnvironment env, BookSource source, String key, {int page = 1}) {
  return _withSource(source, 'searchUrl', () {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.trim().isEmpty) throw RuleException('搜索url不能为空');
    final ruleData = ChainData();
    final request = buildSourceRequest(searchUrl, key: key, page: page, baseUrl: source.bookSourceUrl, source: source);
    final response = _fetch(env, request);
    return _analyzeBookList(env, source, ruleData, request, response);
  });
}

List<SearchBook> _analyzeBookList(
  RuleEnvironment env,
  BookSource source,
  ChainData ruleData,
  SourceRequest request,
  _Response response,
) {
  final baseUrl = response.url;
  final body = response.body;
  final rules = source.ruleSearch;
  final analyzeRule = AnalyzeRule(env, ruleData: ruleData)
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(baseUrl);

  final pattern = source.bookUrlPattern;
  if (pattern != null) {
    final regex = _field('bookUrlPattern', () => SourceRegex.tryCompile(pattern) ?? (throw RuleException('正则无法编译：$pattern')));
    if (regex.matchesEntire(env, baseUrl)) {
      final item = _infoItem(env, source, analyzeRule, request, body, baseUrl, ruleData, response.redirected);
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
  final collections = _field(rules.field('bookList'), () => analyzeRule.getElements(listRule));
  env.checkCancelled();

  if (collections.isEmpty && (pattern == null || pattern.isEmpty)) {
    final item = _infoItem(env, source, analyzeRule, request, body, baseUrl, ruleData, response.redirected);
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
    env.checkCancelled();
    final book = SearchBook(
      bookUrl: '',
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
      variables: ruleData.variables,
    );
    analyzeRule
      ..ruleData = book
      ..setContent(item);
    book.name = formatBookName(_field(rules.field('name'), () => analyzeRule.getStringOf(ruleName)));
    if (book.name.isEmpty) continue;
    book.author = formatBookAuthor(_field(rules.field('author'), () => analyzeRule.getStringOf(ruleAuthor)));
    _optional(rules.field('kind'), () {
      final kind = analyzeRule.getStringListOf(ruleKind)?.join(',');
      book.kind = kind == null ? null : _take(kind, 1000);
    });
    _optional(rules.field('wordCount'), () => book.wordCount = wordCountFormat(analyzeRule.getStringOf(ruleWordCount)));
    _optional(rules.field('lastChapter'), () => book.latestChapterTitle = analyzeRule.getStringOf(ruleLastChapter));
    _optional(rules.field('intro'), () => book.intro = _take(formatHtml(analyzeRule.getStringOf(ruleIntro)), 5000));
    _optional(rules.field('coverUrl'), () {
      final cover = analyzeRule.getStringOf(ruleCoverUrl);
      if (cover.isNotEmpty) book.coverUrl = absoluteUrlFrom(baseUrl, cover);
    });
    book.bookUrl = _field(rules.field('bookUrl'), () => analyzeRule.getStringOf(ruleBookUrl, isUrl: true));
    if (book.bookUrl.isEmpty) book.bookUrl = baseUrl;
    if (baseUrl == book.bookUrl) book.infoHtml = body;
    // 按书籍地址去重，保留第一次出现的
    if (seen.add(book.bookUrl)) books.add(book);
  }
  return reverse ? books.reversed.toList() : books;
}

/// 搜索页当作详情页解析：书籍地址是最终地址（发生过重定向时）或搜索地址（带着选项）。书名为空时没有结果。
SearchBook? _infoItem(
  RuleEnvironment env,
  BookSource source,
  AnalyzeRule analyzeRule,
  SourceRequest request,
  String body,
  String baseUrl,
  ChainData ruleData,
  bool redirected,
) {
  final book = Book(
    bookUrl: redirected ? baseUrl : absoluteUrlFrom(request.url, request.ruleUrl),
    origin: source.bookSourceUrl,
    originName: source.bookSourceName,
    variables: ruleData.variables,
  );
  analyzeRule.ruleData = book;
  _analyzeBookInfo(env, source, book, body, analyzeRule, baseUrl: baseUrl, redirectUrl: baseUrl, canReName: false);
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

// ---------------------------------------------------------------- 详情

/// 详情：已有保存的详情页时直接解析，否则请求书籍地址。目录地址等于书籍地址时保存详情页给目录链路。
Book getBookInfo(RuleEnvironment env, BookSource source, Book book, {bool canReName = true}) {
  return _withSource(source, 'bookUrl', () {
    final infoHtml = book.infoHtml;
    if (infoHtml != null && infoHtml.isNotEmpty) {
      final analyzeRule = AnalyzeRule(env, ruleData: book)
        ..setContent(infoHtml, baseUrl: book.bookUrl)
        ..setRedirectUrl(book.bookUrl);
      _analyzeBookInfo(env, source, book, infoHtml, analyzeRule, baseUrl: book.bookUrl, redirectUrl: book.bookUrl, canReName: canReName);
      return book;
    }
    final request = buildSourceRequest(book.bookUrl, baseUrl: source.bookSourceUrl, source: source);
    final response = _fetch(env, request);
    final analyzeRule = AnalyzeRule(env, ruleData: book)
      ..setContent(response.body, baseUrl: book.bookUrl)
      ..setRedirectUrl(response.url);
    _analyzeBookInfo(env, source, book, response.body, analyzeRule, baseUrl: book.bookUrl, redirectUrl: response.url, canReName: canReName);
    return book;
  });
}

void _analyzeBookInfo(
  RuleEnvironment env,
  BookSource source,
  Book book,
  String body,
  AnalyzeRule analyzeRule, {
  required String baseUrl,
  required String redirectUrl,
  required bool canReName,
}) {
  final rules = source.ruleBookInfo;
  final init = rules['init'];
  if (init != null && init.trim().isNotEmpty) {
    env.checkCancelled();
    final element = _field(rules.field('init'), () => analyzeRule.getElement(init));
    // MD3 在这里 setContent(null) 抛 AssertionError（D12）
    if (element == null) throw RuleException('详情 init 取不到', field: rules.field('init'));
    analyzeRule.setContent(element);
  }
  final mCanReName = canReName && (rules['canReName']?.trim().isNotEmpty ?? false);
  env.checkCancelled();
  final name = formatBookName(_field(rules.field('name'), () => analyzeRule.getString(rules['name'])));
  if (name.isNotEmpty && (mCanReName || book.name.isEmpty)) book.name = name;
  final author = formatBookAuthor(_field(rules.field('author'), () => analyzeRule.getString(rules['author'])));
  if (author.isNotEmpty && (mCanReName || book.author.isEmpty)) book.author = author;
  _optional(rules.field('kind'), () {
    final kind = analyzeRule.getStringList(rules['kind'])?.join(',');
    if (kind != null && kind.isNotEmpty) book.kind = _take(kind, 1000);
  });
  _optional(rules.field('wordCount'), () {
    final wordCount = wordCountFormat(analyzeRule.getString(rules['wordCount']));
    if (wordCount.isNotEmpty) book.wordCount = wordCount;
  });
  _optional(rules.field('lastChapter'), () {
    final lastChapter = analyzeRule.getString(rules['lastChapter']);
    if (lastChapter.isNotEmpty) book.latestChapterTitle = lastChapter;
  });
  _optional(rules.field('intro'), () {
    final intro = analyzeRule.getString(rules['intro']).trimLeft();
    if (intro.startsWith('<usehtml>') || intro.startsWith('<md>') || intro.startsWith('<useweb>')) {
      book.intro = intro;
    } else {
      final formatted = _take(formatHtml(intro), 5000);
      if (formatted.isNotEmpty) book.intro = formatted;
    }
  });
  _optional(rules.field('coverUrl'), () {
    final cover = analyzeRule.getString(rules['coverUrl']);
    if (cover.isNotEmpty) book.coverUrl = absoluteUrlFrom(redirectUrl, cover);
  });
  env.checkCancelled();
  if (source.bookSourceType != BookSourceType.file) {
    book.tocUrl = _field(rules.field('tocUrl'), () => analyzeRule.getString(rules['tocUrl'], isUrl: true));
    if (book.tocUrl.isEmpty) book.tocUrl = baseUrl;
    if (book.tocUrl == baseUrl) book.tocHtml = body;
  } else {
    book.downloadUrls = _field(rules.field('downloadUrls'), () => analyzeRule.getStringList(rules['downloadUrls'], isUrl: true));
    if (book.downloadUrls == null || book.downloadUrls!.isEmpty) {
      throw RuleException('下载链接为空', field: rules.field('downloadUrls'));
    }
  }
}

// ---------------------------------------------------------------- 目录

/// 目录：目录就在详情页时直接解析保存的页面，否则请求目录地址。支持串行和并发两种多页目录。
List<BookChapter> getChapterList(RuleEnvironment env, BookSource source, Book book) {
  return _withSource(source, 'tocUrl', () {
    final rules = source.ruleToc;
    final formatJs = rules['formatJs'];
    if (formatJs != null && formatJs.trim().isNotEmpty) throw NeedsJsException(formatJs, field: rules.field('formatJs'));
    final tocHtml = book.tocHtml;
    if (book.bookUrl == book.tocUrl && tocHtml != null && tocHtml.isNotEmpty) {
      return _analyzeChapterList(env, source, book, baseUrl: book.tocUrl, redirectUrl: book.tocUrl, body: tocHtml);
    }
    final request = buildSourceRequest(book.tocUrl, baseUrl: book.bookUrl, source: source);
    final response = _fetch(env, request);
    return _analyzeChapterList(env, source, book, baseUrl: book.tocUrl, redirectUrl: response.url, body: response.body);
  });
}

List<BookChapter> _analyzeChapterList(
  RuleEnvironment env,
  BookSource source,
  Book book, {
  required String baseUrl,
  required String redirectUrl,
  required String body,
}) {
  final rules = source.ruleToc;
  var listRule = rules['chapterList'] ?? '';
  var reverse = false;
  if (listRule.startsWith('-')) {
    reverse = true;
    listRule = listRule.substring(1);
  }
  if (listRule.startsWith('+')) listRule = listRule.substring(1);

  final chapters = <BookChapter>[];
  final visited = <String>[redirectUrl];
  var page = _tocPage(env, source, book, baseUrl, redirectUrl, body, listRule, getNextUrl: true);
  chapters.addAll(page.chapters);
  if (page.nextUrls.length == 1) {
    // 只有一个下一页：串行翻页，访问过的不再访问
    var nextUrl = page.nextUrls.single;
    while (nextUrl.isNotEmpty && !visited.contains(nextUrl)) {
      visited.add(nextUrl);
      final response = _fetch(env, buildSourceRequest(nextUrl, source: source));
      page = _tocPage(env, source, book, nextUrl, nextUrl, response.body, listRule, getNextUrl: true);
      nextUrl = page.nextUrls.firstOrNull ?? '';
      chapters.addAll(page.chapters);
    }
  } else if (page.nextUrls.length > 1) {
    // 首页列出了全部分页：并发请求这一批，子页不再找下一页
    final requests = [for (final url in page.nextUrls) buildSourceRequest(url, source: source)];
    final responses = _fetchAll(env, requests);
    for (final (index, response) in responses.indexed) {
      final pageData = _tocPage(env, source, book, page.nextUrls[index], response.url, response.body, listRule, getNextUrl: false);
      chapters.addAll(pageData.chapters);
    }
  }
  if (chapters.isEmpty) throw RuleException('目录为空', field: rules.field('chapterList'));

  // 没有 - 时：倒过来去重再倒回来，重复的保留最后一次；有 - 时：去重后整体倒序
  var list = reverse ? chapters : chapters.reversed.toList();
  final seen = <String>{};
  list = [
    for (final chapter in list)
      if (seen.add(chapter.url)) chapter,
  ];
  list = list.reversed.toList();
  for (final (index, chapter) in list.indexed) {
    chapter.index = index;
  }
  return list;
}

typedef _TocPage = ({List<BookChapter> chapters, List<String> nextUrls});

_TocPage _tocPage(
  RuleEnvironment env,
  BookSource source,
  Book book,
  String baseUrl,
  String redirectUrl,
  String body,
  String listRule, {
  required bool getNextUrl,
}) {
  final rules = source.ruleToc;
  final analyzeRule = AnalyzeRule(env, ruleData: book)
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(redirectUrl);
  final elements = _field(rules.field('chapterList'), () => analyzeRule.getElements(listRule));
  final nextUrls = <String>[];
  final nextRule = rules['nextTocUrl'];
  if (getNextUrl && nextRule != null && nextRule.isNotEmpty) {
    final urls = _field(rules.field('nextTocUrl'), () => analyzeRule.getStringList(nextRule, isUrl: true));
    for (final url in urls ?? const <String>[]) {
      if (url != redirectUrl) nextUrls.add(url);
    }
  }
  env.checkCancelled();
  final chapters = <BookChapter>[];
  if (elements.isEmpty) return (chapters: chapters, nextUrls: nextUrls);

  final nameRule = analyzeRule.prepare(rules['chapterName']);
  final urlRule = analyzeRule.prepare(rules['chapterUrl']);
  final vipRule = analyzeRule.prepare(rules['isVip']);
  final payRule = analyzeRule.prepare(rules['isPay']);
  final updateTimeRule = analyzeRule.prepare(rules['updateTime']);
  final volumeRule = analyzeRule.prepare(rules['isVolume']);
  for (final (index, item) in elements.indexed) {
    env.checkCancelled();
    analyzeRule.setContent(item);
    final chapter = BookChapter(bookUrl: book.bookUrl, baseUrl: redirectUrl);
    analyzeRule.chapter = chapter;
    chapter.title = _field(rules.field('chapterName'), () => analyzeRule.getStringOf(nameRule));
    chapter.url = _field(rules.field('chapterUrl'), () => analyzeRule.getStringOf(urlRule));
    chapter.tag = _field(rules.field('updateTime'), () => analyzeRule.getStringOf(updateTimeRule));
    chapter.isVolume = isTrue(_field(rules.field('isVolume'), () => analyzeRule.getStringOf(volumeRule)));
    if (chapter.url.isEmpty) chapter.url = chapter.isVolume ? '${chapter.title}$index' : baseUrl;
    if (chapter.title.isEmpty) continue;
    chapter.isVip = isTrue(_field(rules.field('isVip'), () => analyzeRule.getStringOf(vipRule)));
    chapter.isPay = isTrue(_field(rules.field('isPay'), () => analyzeRule.getStringOf(payRule)));
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
  return _withSource(source, 'ruleContent.content', () {
    if (source.bookSourceType == BookSourceType.file) throw RuleException('不支持的书源类型');
    final rules = source.ruleContent;
    final contentRule = rules['content'];
    if (contentRule == null || contentRule.isEmpty) return ChapterContent(chapter.url, title: chapter.title);
    if (chapter.isVolume && chapter.url.startsWith(chapter.title)) {
      return ChapterContent(chapter.tag ?? '', title: chapter.title);
    }
    final absoluteUrl = chapterAbsoluteUrl(chapter);
    final tocHtml = book.tocHtml;
    if (chapter.url == book.bookUrl && tocHtml != null && tocHtml.isNotEmpty) {
      return _analyzeContent(env, source, book, chapter, baseUrl: absoluteUrl, redirectUrl: absoluteUrl, body: tocHtml, nextChapterUrl: nextChapterUrl);
    }
    final response = _fetch(env, buildSourceRequest(absoluteUrl, baseUrl: book.tocUrl, source: source));
    return _analyzeContent(env, source, book, chapter, baseUrl: absoluteUrl, redirectUrl: response.url, body: response.body, nextChapterUrl: nextChapterUrl);
  });
}

ChapterContent _analyzeContent(
  RuleEnvironment env,
  BookSource source,
  Book book,
  BookChapter chapter, {
  required String baseUrl,
  required String redirectUrl,
  required String body,
  String? nextChapterUrl,
}) {
  final rules = source.ruleContent;
  final pages = <String>[];
  final visited = <String>[redirectUrl];
  final analyzeRule = AnalyzeRule(env, ruleData: book, chapter: chapter)
    ..setContent(body, baseUrl: baseUrl)
    ..setRedirectUrl(redirectUrl);

  var page = _contentPage(env, source, book, chapter, baseUrl, redirectUrl, body, getNextUrl: true);
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
      final response = _fetch(env, buildSourceRequest(nextUrl, source: source));
      page = _contentPage(env, source, book, chapter, nextUrl, response.url, response.body, getNextUrl: true);
      nextUrl = page.nextUrls.firstOrNull ?? '';
      pages.add(page.content);
    }
  } else if (page.nextUrls.length > 1) {
    final responses = _fetchAll(env, [for (final url in page.nextUrls) buildSourceRequest(url, source: source)]);
    for (final (index, response) in responses.indexed) {
      pages.add(_contentPage(env, source, book, chapter, page.nextUrls[index], response.url, response.body, getNextUrl: false).content);
    }
  }

  final subRule = rules['subContent'];
  if (subRule != null && subRule.trim().isNotEmpty) {
    final raw = _field(rules.field('subContent'), () => analyzeRule.getString(subRule, unescape: false)).trim();
    final sub = raw.toLowerCase().startsWith('http') ? _fetch(env, buildSourceRequest(raw, source: source)).body : raw;
    if (sub.trim().isNotEmpty && source.bookSourceType == BookSourceType.text) pages.add(sub);
  }
  var content = pages.join('\n');

  var title = chapter.title;
  String? reviewImg;
  final titleRule = rules['title'];
  if (titleRule != null && titleRule.trim().isNotEmpty) {
    String? found;
    try {
      found = analyzeRule.getString(titleRule);
    } on RuleException {
      // MD3 用 runCatching 吞掉
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
    content = _field(rules.field('replaceRegex'), () => analyzeRule.getString(replaceRegex, content: content));
    content = content.split('\n').map((line) => '$paragraphIndent$line').join('\n');
  }
  if (!chapter.isVolume && content.trim().isEmpty) throw RuleException('正文为空', field: rules.field('content'));
  return ChapterContent(content, title: title, reviewImg: reviewImg);
}

typedef _ContentPage = ({String content, List<String> nextUrls});

_ContentPage _contentPage(
  RuleEnvironment env,
  BookSource source,
  Book book,
  BookChapter chapter,
  String baseUrl,
  String redirectUrl,
  String body, {
  required bool getNextUrl,
}) {
  final rules = source.ruleContent;
  final analyzeRule = AnalyzeRule(env, ruleData: book, chapter: chapter)..setContent(body, baseUrl: baseUrl);
  final redirect = analyzeRule.setRedirectUrl(redirectUrl);
  var content = _field(rules.field('content'), () => analyzeRule.getString(rules['content'], unescape: false));
  if (source.bookSourceType != BookSourceType.audio && source.bookSourceType != BookSourceType.video) {
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
    nextUrls.addAll(_field(rules.field('nextContentUrl'), () => analyzeRule.getStringList(nextRule, isUrl: true)) ?? const []);
  }
  env.checkCancelled();
  return (content: content, nextUrls: nextUrls);
}

// ---------------------------------------------------------------- 公共

typedef _Response = ({String url, String body, bool redirected});

/// 请求之前检查取消；选项 `type` 不为 null 时结果是响应字节的十六进制（地址是请求地址）。
_Response _fetch(RuleEnvironment env, SourceRequest request) {
  env.checkCancelled();
  final result = env.fetch(request.http);
  return _toResponse(request, result);
}

List<_Response> _fetchAll(RuleEnvironment env, List<SourceRequest> requests) {
  env.checkCancelled();
  final results = env.fetchAll([for (final request in requests) request.http]);
  return [for (final (index, result) in results.indexed) _toResponse(requests[index], result)];
}

_Response _toResponse(SourceRequest request, HttpResult result) {
  if (request.type != null) return (url: request.url, body: hexResponseBody(result), redirected: false);
  return (url: result.url, body: decodeResponseBody(result), redirected: result.redirected);
}

/// 给出错的规则补上字段。
T _field<T>(String field, T Function() body) {
  try {
    return body();
  } on RuleEngineException catch (e) {
    e.field ??= field;
    rethrow;
  }
}

/// 可选字段：规则错误吞掉（MD3 的 try/catch），需要 JS、WebView 的错误照常抛出。
void _optional(String field, void Function() body) {
  try {
    body();
  } on RuleException {
    // 和 MD3 一样只记日志
  } on FormatException {
    // 字数超出范围等
  } on NeedsJsException catch (e) {
    e.field ??= field;
    rethrow;
  } on NeedsWebViewException catch (e) {
    e.field ??= field;
    rethrow;
  }
}

/// 给链路里的错误补上书源名，没有字段时补上 [field]。
T _withSource<T>(BookSource source, String field, T Function() body) {
  try {
    return body();
  } on RuleEngineException catch (e) {
    e.sourceName ??= source.bookSourceName;
    e.field ??= field;
    rethrow;
  }
}

/// Kotlin 的 `String.take(n)`。
String _take(String text, int n) => text.length <= n ? text : text.substring(0, n);
