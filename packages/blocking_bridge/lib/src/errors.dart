/// 任务被取消。提交方从 `WorkerPool.run` 收到它；worker 里的任务代码在取消后调用
/// `callHost` / `throwIfCancelled` 时也会收到它，不要吞掉。
final class TaskCancelledException implements Exception {
  const TaskCancelledException();

  @override
  String toString() => 'TaskCancelledException: 任务已取消';
}

/// 任务超过截止时间。
final class TaskTimeoutException implements Exception {
  const TaskTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'TaskTimeoutException: 任务超过截止时间（${timeout.inMilliseconds}ms）';
}

/// 执行任务的 worker isolate 意外退出。
final class WorkerExitedException implements Exception {
  const WorkerExitedException([this.cause]);

  /// worker 里未捕获的错误（如果有）。
  final String? cause;

  @override
  String toString() => 'WorkerExitedException: worker 异常退出${cause == null ? '' : '：$cause'}';
}

/// 主 isolate 处理宿主请求失败，在 worker 里由 `callHost` 抛出，可以捕获。
final class HostCallException implements Exception {
  const HostCallException(this.message);

  final String message;

  @override
  String toString() => 'HostCallException: $message';
}
