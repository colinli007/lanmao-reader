/// Legado 书源规则引擎。
///
/// 核心层（规则解析、请求构造、四条链路）是同步代码，网络和取消通过 [RuleEnvironment] 注入。
/// 在应用里：主 isolate 用 [RuleHost] 处理网络，worker 里用任务工厂执行链路：
///
/// ```dart
/// final host = RuleHost(onLog: (log) => print(log)); // 书源 JS 的调试日志
/// final pool = WorkerPool(host.handle, size: 4);
/// final books = await pool.run(searchTask(source, '三体'));
/// ```
///
/// 书源里的 JS 在 worker 内的 quickjs-ng 上执行；缓存、书源变量、登录头和 Cookie 放在主 isolate 的 [RuleHost] 上，
/// 由 [SourceStore] 保存（默认只在内存里）。
library;

export 'src/chain/chains.dart'
    show SearchStep, chapterAbsoluteUrl, finishSearch, getBookInfo, getChapterList, getContent, getContentImage, prepareSearch, searchBooks;
export 'src/chain/models.dart';
export 'src/core/environment.dart';
export 'src/core/errors.dart';
export 'src/host/cookie_store.dart' show CookieStore;
export 'src/host/rule_host.dart';
export 'src/host/source_store.dart' show MemorySourceStore, SourceStore, runStoreRequest;
export 'src/request/analyze_url.dart' show defaultUserAgent;
export 'src/source/book_source.dart';
export 'src/source/replace_rule.dart';
export 'src/worker/tasks.dart';
export 'src/worker/worker_environment.dart' show WorkerRuleEnvironment;
