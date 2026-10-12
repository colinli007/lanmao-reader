/// Legado 书源规则引擎。
///
/// 核心层（规则解析、请求构造、四条链路）是同步代码，网络和取消通过 [RuleEnvironment] 注入。
/// 在应用里：主 isolate 用 [RuleHost] 处理网络，worker 里用任务工厂执行链路：
///
/// ```dart
/// final host = RuleHost();
/// final pool = WorkerPool(host.handle, size: 4);
/// final books = await pool.run(searchTask(source, '三体'));
/// ```
library;

export 'src/chain/chains.dart' show chapterAbsoluteUrl, getBookInfo, getChapterList, getContent, searchBooks;
export 'src/chain/models.dart';
export 'src/core/environment.dart';
export 'src/core/errors.dart';
export 'src/host/rule_host.dart';
export 'src/source/book_source.dart';
export 'src/worker/tasks.dart';
export 'src/worker/worker_environment.dart' show WorkerRuleEnvironment;
