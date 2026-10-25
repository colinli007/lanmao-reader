import '../chain/chains.dart';
import '../chain/models.dart';
import '../core/environment.dart';
import '../source/book_source.dart';
import '../source/replace_rule.dart';
import 'worker_environment.dart';

/// 四条链路的任务工厂，交给 `WorkerPool.run`。
///
/// 必须是顶层函数：Dart 闭包会捕获整个外层上下文，在方法里构造的闭包可能带上不能跨 isolate 传递的对象。
/// 这里的闭包只捕获参数，书源、书籍、章节都是普通对象，可以传给 worker。
List<SearchBook> Function() searchTask(BookSource source, String key, {int page = 1}) =>
    () => searchBooks(const WorkerRuleEnvironment(), source, key, page: page);

/// 分段搜索的两段（见 [prepareSearch]）：第一段交回的 [SearchStep] 由提交方发出请求，再连同响应交给第二段。
SearchStep Function() prepareSearchTask(BookSource source, String key) =>
    () => prepareSearch(const WorkerRuleEnvironment(), source, key);

List<SearchBook> Function() finishSearchTask(SearchStep step, HttpResult result) =>
    () => finishSearch(step, result);

Book Function() bookInfoTask(BookSource source, Book book, {bool canReName = true}) =>
    () => getBookInfo(const WorkerRuleEnvironment(), source, book, canReName: canReName);

/// 目录任务的结果：章节，以及目录链路更新过的书籍（章节数、当前章节名、JS 写入的变量等）。
/// 任务在 worker 里执行的是书籍的副本，所以要把它一并交回。
typedef TocResult = ({Book book, List<BookChapter> chapters});

TocResult Function() chapterListTask(BookSource source, Book book) => () {
  final chapters = getChapterList(const WorkerRuleEnvironment(), source, book);
  return (book: book, chapters: chapters);
};

ChapterContent Function() contentTask(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl}) =>
    () => getContent(const WorkerRuleEnvironment(), source, book, chapter, nextChapterUrl: nextChapterUrl);

/// 替换净化规则（add-replace-rules 设计 D2、D3）：执行一条正则规则、载入规则 JSON、校验一条规则，都要用到 worker 里的正则引擎。
String Function() replaceTask(String input, String pattern, String replacement) =>
    () => applyReplaceRule(const WorkerRuleEnvironment(), input, pattern, replacement);

ReplaceRuleLoadResult Function() loadReplaceRulesTask(String text) => () => loadReplaceRules(text);

String? Function() replaceRuleErrorTask(String pattern, {required bool isRegex}) =>
    () => replaceRuleError(pattern, isRegex: isRegex);
