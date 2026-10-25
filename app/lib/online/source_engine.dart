import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import 'batch.dart';

/// 四条链路和替换净化规则的执行方。界面和控制器只依赖这个接口，测试换成假的实现。
abstract interface class SourceEngine {
  /// 批量任务，经限流器提交。
  Future<List<SearchBook>> search(BookSource source, String key, Batch batch);

  Future<Book> bookInfo(BookSource source, Book book);

  /// [batch] 不为空时是批量任务（书架更新），经限流器提交。
  Future<TocResult> chapterList(BookSource source, Book book, {Batch? batch});

  Future<ChapterContent> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl});

  /// 执行一条正则替换规则，超过规则的超时时间时抛出 [TaskTimeoutException]（add-replace-rules 设计 D2、D5）。
  Future<String> replace(String input, ReplaceRule rule);

  /// 载入替换规则 JSON，内容不是 JSON 时抛出 [FormatException]（设计 D3）。
  Future<ReplaceRuleLoadResult> loadReplaceRules(String text);

  /// 规则不可用的原因，可用时为 null（设计 D3）。
  Future<String?> replaceRuleError(String pattern, {required bool isRegex});
}

/// 主 isolate 上发出请求的函数（`RuleHost.execute`）：[cancelled] 完成时中断请求。
typedef HttpExecutor = Future<HttpResult> Function(HttpRequest request, {Future<void>? cancelled});

/// 在 worker 池上执行。批量任务同时最多 [batchLimit] 个（池大小减 2，留给交互任务），交互任务直接提交（设计 D6）。
///
/// 搜索分两段在池里执行，中间的请求由 [_execute] 在主 isolate 上发出：等网络时不占 worker，
/// 同时等网络的书源最多 [networkLimit] 个。单个书源的搜索超过 [searchTimeout] 按超时失败。
final class PoolSourceEngine implements SourceEngine {
  PoolSourceEngine(
    this._pool,
    this._execute, {
    int batchLimit = 4,
    int networkLimit = 32,
    this.searchTimeout = const Duration(seconds: 30),
  }) : _limiter = BatchLimiter(batchLimit),
       _network = BatchLimiter(networkLimit);

  final WorkerPool _pool;
  final HttpExecutor _execute;
  final BatchLimiter _limiter;
  final BatchLimiter _network;
  final Duration searchTimeout;

  /// 三步各自排队：构造请求（批量限流）→ 发出请求（网络限流）→ 解析响应（批量限流）。
  @override
  Future<List<SearchBook>> search(BookSource source, String key, Batch batch) async {
    final budget = _SearchBudget(searchTimeout);
    final step = await _limiter.run(
      batch,
      (token) => budget.run((remaining) => _pool.run(prepareSearchTask(source, key), timeout: remaining, cancelToken: token)),
    );
    final result = await _network.run(batch, (_) => budget.run((remaining) => _fetch(step.http, remaining, batch)));
    return _limiter.run(
      batch,
      (token) => budget.run((remaining) => _pool.run(finishSearchTask(step, result), timeout: remaining, cancelToken: token)),
    );
  }

  /// 发出请求，和预算到期、批次停止比谁先到；后两者先到时中断请求，不等连接关闭。
  /// 请求失败包成 [HostCallException]，和 worker 里经阻塞桥发请求时的错误相同。
  Future<HttpResult> _fetch(HttpRequest request, Duration remaining, Batch batch) async {
    final expired = Completer<void>();
    final timer = Timer(remaining, expired.complete);
    Future<HttpResult> execute() async {
      try {
        return await _execute(request, cancelled: Future.any([expired.future, batch.stopped]));
      } catch (error) {
        throw HostCallException('$error');
      }
    }

    try {
      return await Future.any([
        execute(),
        expired.future.then((_) => throw TaskTimeoutException(remaining)),
        batch.stopped.then((_) => throw const TaskCancelledException()),
      ]);
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<Book> bookInfo(BookSource source, Book book) => _pool.run(bookInfoTask(source, book));

  @override
  Future<TocResult> chapterList(BookSource source, Book book, {Batch? batch}) => batch == null
      ? _pool.run(chapterListTask(source, book))
      : _limiter.run(batch, (token) => _pool.run(chapterListTask(source, book), cancelToken: token));

  @override
  Future<ChapterContent> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl}) =>
      _pool.run(contentTask(source, book, chapter, nextChapterUrl: nextChapterUrl));

  @override
  Future<String> replace(String input, ReplaceRule rule) =>
      _pool.run(replaceTask(input, rule.pattern, rule.replacement), timeout: rule.timeout);

  @override
  Future<ReplaceRuleLoadResult> loadReplaceRules(String text) => _pool.run(loadReplaceRulesTask(text));

  @override
  Future<String?> replaceRuleError(String pattern, {required bool isRegex}) =>
      _pool.run(replaceRuleErrorTask(pattern, isRegex: isRegex));
}

/// 一个书源的搜索预算（设计 D4）：只在三步执行时扣减，排队的时间不算。哪一步超时都按整个预算报告。
final class _SearchBudget {
  _SearchBudget(this.total);

  final Duration total;
  final Stopwatch _used = Stopwatch();

  Future<R> run<R>(Future<R> Function(Duration remaining) step) async {
    final remaining = total - _used.elapsed;
    if (remaining <= Duration.zero) throw TaskTimeoutException(total);
    _used.start();
    try {
      return await step(remaining);
    } on TaskTimeoutException {
      throw TaskTimeoutException(total);
    } finally {
      _used.stop();
    }
  }
}
