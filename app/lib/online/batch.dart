import 'dart:async';
import 'dart:collection';

import 'package:blocking_bridge/blocking_bridge.dart';

/// 一批后台任务（一次搜索、一次书架更新），共用一个取消令牌。[stop] 取消池里的任务，
/// 并让还在限流器里排队的任务以 [TaskCancelledException] 结束、不再提交。
final class Batch {
  final CancelToken token = CancelToken();
  final Set<Completer<void>> _waiting = {};

  bool get isStopped => token.isCancelled;

  void stop() {
    token.cancel();
    for (final waiter in _waiting) {
      waiter.completeError(const TaskCancelledException());
    }
    _waiting.clear();
  }
}

/// 批量任务的限流器（设计 D6）：同时最多 [max] 个在池里，池的其余 worker 留给详情、目录、正文这些交互任务。
final class BatchLimiter {
  BatchLimiter(this.max) : assert(max > 0);

  final int max;
  int _running = 0;
  final Queue<(Batch, Completer<void>)> _queue = Queue();

  Future<R> run<R>(Batch batch, Future<R> Function(CancelToken token) submit) async {
    await _acquire(batch);
    try {
      return await submit(batch.token);
    } finally {
      _release();
    }
  }

  Future<void> _acquire(Batch batch) {
    if (batch.isStopped) return Future.error(const TaskCancelledException());
    if (_running < max) {
      _running++;
      return Future.value();
    }
    final waiter = Completer<void>();
    batch._waiting.add(waiter);
    _queue.add((batch, waiter));
    return waiter.future;
  }

  void _release() {
    _running--;
    while (_queue.isNotEmpty) {
      final (batch, waiter) = _queue.removeFirst();
      if (waiter.isCompleted) continue; // 所在的批次已经停止
      batch._waiting.remove(waiter);
      _running++;
      waiter.complete();
      return;
    }
  }
}
