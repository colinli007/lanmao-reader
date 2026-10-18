import 'package:rule_engine/rule_engine.dart';

import '../storage/database.dart';
import '../storage/write_queue.dart';

/// 落盘的书源级状态（设计 D4）：内存里的值是唯一的真相，数据库是它的镜像。
///
/// 引擎的 [SourceStore] 是同步接口，所以启动时把未过期的行全部载入内存；读只读内存，
/// 写先改内存（立即对所有 worker 可见），再交给落盘队列。`putMemory` 等只在内存里，不落盘。
final class PersistentSourceStore implements SourceStore {
  PersistentSourceStore._(this._db, this._queue, this._now) : _memory = MemorySourceStore(now: _now);

  final AppDatabase _db;
  final WriteQueue _queue;
  final DateTime Function() _now;
  final MemorySourceStore _memory;

  static Future<PersistentSourceStore> load(AppDatabase db, WriteQueue queue, {DateTime Function()? now}) async {
    final clock = now ?? DateTime.now;
    final store = PersistentSourceStore._(db, queue, clock);
    final loadedAt = clock();
    for (final row in await db.loadSourceKv(loadedAt)) {
      store._memory.put(row.key, row.value, ttl: row.deadline?.difference(loadedAt));
    }
    return store;
  }

  @override
  String? get(String key) => _memory.get(key);

  @override
  void put(String key, String value, {Duration? ttl}) {
    _memory.put(key, value, ttl: ttl);
    final deadline = ttl == null ? null : _now().add(ttl);
    _queue.add(() => _db.putSourceKv(key, value, deadline));
  }

  @override
  void delete(String key) {
    _memory.delete(key);
    _queue.add(() => _db.deleteSourceKv(key));
  }

  @override
  Object? getMemory(String key) => _memory.getMemory(key);

  @override
  void putMemory(String key, Object? value) => _memory.putMemory(key, value);

  @override
  void deleteMemory(String key) => _memory.deleteMemory(key);
}
