import '../chain/chains.dart';
import '../chain/models.dart';
import '../source/book_source.dart';
import 'worker_environment.dart';

/// 四条链路的任务工厂，交给 `WorkerPool.run`。
///
/// 必须是顶层函数：Dart 闭包会捕获整个外层上下文，在方法里构造的闭包可能带上不能跨 isolate 传递的对象。
/// 这里的闭包只捕获参数，书源、书籍、章节都是普通对象，可以传给 worker。
List<SearchBook> Function() searchTask(BookSource source, String key, {int page = 1}) =>
    () => searchBooks(const WorkerRuleEnvironment(), source, key, page: page);

Book Function() bookInfoTask(BookSource source, Book book, {bool canReName = true}) =>
    () => getBookInfo(const WorkerRuleEnvironment(), source, book, canReName: canReName);

List<BookChapter> Function() chapterListTask(BookSource source, Book book) =>
    () => getChapterList(const WorkerRuleEnvironment(), source, book);

ChapterContent Function() contentTask(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl}) =>
    () => getContent(const WorkerRuleEnvironment(), source, book, chapter, nextChapterUrl: nextChapterUrl);
