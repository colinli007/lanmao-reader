import '../core/source_state.dart';
import 'cookie_store.dart';

/// 书源级的键值存储：缓存（`cache.*`）、书源变量、登录头、登录信息，键带前缀区分（与 MD3 的 `CacheManager` 相同）。
///
/// 主 isolate 上只有一份，所有 worker 共用。这里只定义接口和内存实现，以后的存储层实现同一接口来落盘。
abstract interface class SourceStore {
  /// 未过期的值，没有时为 null。
  String? get(String key);

  /// [ttl] 为 null 时不过期。
  void put(String key, String value, {Duration? ttl});

  void delete(String key);

  /// 只在内存里的值（`cache.putMemory`），不落盘。
  Object? getMemory(String key);

  void putMemory(String key, Object? value);

  void deleteMemory(String key);
}

/// 内存实现。[now] 用于测试过期。
final class MemorySourceStore implements SourceStore {
  MemorySourceStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, ({String value, DateTime? deadline})> _values = {};
  final Map<String, Object?> _memory = {};

  @override
  String? get(String key) {
    final entry = _values[key];
    if (entry == null) return null;
    final deadline = entry.deadline;
    if (deadline != null && !_now().isBefore(deadline)) {
      _values.remove(key);
      return null;
    }
    return entry.value;
  }

  @override
  void put(String key, String value, {Duration? ttl}) =>
      _values[key] = (value: value, deadline: ttl == null ? null : _now().add(ttl));

  @override
  void delete(String key) => _values.remove(key);

  @override
  Object? getMemory(String key) => _memory[key];

  @override
  void putMemory(String key, Object? value) => _memory[key] = value;

  @override
  void deleteMemory(String key) => _memory.remove(key);
}

/// 在主 isolate 上执行一次 [StoreRequest]。worker 的宿主请求和测试环境都走这里，语义只有一份。
Object? runStoreRequest(StoreRequest request, SourceStore store, CookieStore cookies) {
  final key = request.key;
  switch (request.op) {
    case StoreOp.get:
      return store.get(key);
    case StoreOp.put:
      final seconds = request.saveSeconds;
      store.put(key, request.value as String, ttl: seconds > 0 ? Duration(seconds: seconds) : null);
    case StoreOp.delete:
      store.delete(key);
    case StoreOp.getMemory:
      return store.getMemory(key);
    case StoreOp.putMemory:
      store.putMemory(key, request.value);
    case StoreOp.deleteMemory:
      store.deleteMemory(key);
    case StoreOp.getCookie:
      return cookies.getCookie(key);
    case StoreOp.setCookie:
      cookies.setCookie(key, request.value as String? ?? '');
    case StoreOp.replaceCookie:
      cookies.replaceCookie(key, request.value as String? ?? '');
    case StoreOp.removeCookie:
      cookies.removeCookie(key);
  }
  return null;
}
