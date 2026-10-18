import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import '../storage/database.dart';
import '../storage/write_queue.dart';
import 'persistent_source_store.dart';

/// 主 isolate 上的引擎：落盘的书源级状态和 Cookie、RuleHost、worker 池（设计 D4、D5、D6）。
///
/// 书源级状态和持久 Cookie 在建 RuleHost 之前全部载入内存，之后的写入经 [queue] 落盘。
final class EngineStack {
  EngineStack._(this.host, this.pool);

  /// 全 app 一个池，最多 6 个 worker（设计 D6）：同一个 isolate group 里同时运行的 isolate 最多 8 个
  /// （Dart VM 的 MaxMutatorThreadCount：16MB 新生代 / 512KB TLAB / 4），阻塞在宿主请求里的 worker 也占一个；
  /// 再给主 isolate 和 drift 的后台 isolate 各留一个。超过之后主 isolate 要等 120ms 抢占才能处理宿主请求，
  /// 越多越慢，16 个时会卡死。
  static const poolSize = 6;

  final RuleHost host;
  final WorkerPool pool;

  static Future<EngineStack> open(
    AppDatabase db,
    WriteQueue queue, {
    required void Function(SourceLog log) onLog,
    int poolSize = poolSize,
    DateTime Function()? now,
  }) async {
    final store = await PersistentSourceStore.load(db, queue, now: now);
    final cookies = CookieStore(
      persistent: await db.loadCookies(),
      onPersistentChanged: (domain, cookie) => queue.add(() => db.putCookie(domain, cookie)),
    );
    final host = RuleHost(store: store, cookieStore: cookies, onLog: onLog);
    return EngineStack._(host, WorkerPool(host.handle, size: poolSize));
  }

  void close() => pool.close();
}
