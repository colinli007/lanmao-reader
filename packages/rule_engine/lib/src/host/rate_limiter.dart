/// MD3 的 `ConcurrentRateLimiter`：按书源地址在所有 worker 之间统一限速，按请求的发起时刻计数，请求结束时不释放。
///
/// `N`：两次发起至少间隔 N 毫秒；`a/b`：从窗口内第一次发起起算，每 b 毫秒最多 a 次。为空、为 `0` 时不限速，
/// 解析不了的部分按 MD3 的默认值（次数 1，间隔 0，即不限速）。只在主 isolate 上使用，不需要加锁。
final class RateLimiter {
  RateLimiter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Record> _records = {};

  /// 等到可以发起请求。
  Future<void> acquire(String key, String? concurrentRate) async {
    while (true) {
      final wait = _tryStart(key, concurrentRate);
      if (wait <= 0) return;
      await Future<void>.delayed(Duration(milliseconds: wait));
    }
  }

  /// 可以发起时返回 0 并记一次，否则返回还要等的毫秒数。
  int _tryStart(String key, String? rate) {
    if (rate == null || rate.isEmpty || rate == '0') return 0;
    final now = _clock().millisecondsSinceEpoch;
    final record = _records[key];
    if (record == null) {
      final slash = rate.indexOf('/');
      _records[key] = slash > 0
          ? _Record(now, int.tryParse(rate.substring(0, slash)) ?? 1, int.tryParse(rate.substring(slash + 1)) ?? 0)
          : _Record(now, 1, int.tryParse(rate) ?? 0);
      return 0;
    }
    final nextTime = record.time + record.interval;
    if (now >= nextTime) {
      record
        ..time = now
        ..frequency = 1;
      return 0;
    }
    if (record.frequency < record.accessLimit) {
      record.frequency++;
      return 0;
    }
    return nextTime - now;
  }
}

final class _Record {
  _Record(this.time, this.accessLimit, this.interval);

  int time;
  final int accessLimit;
  final int interval;
  int frequency = 1;
}
