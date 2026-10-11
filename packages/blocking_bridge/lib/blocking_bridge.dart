/// 阻塞桥：在后台工作 isolate 里同步执行任务，任务可以同步等待主 isolate 的异步结果。
///
/// 书源 JS 的 `var html = java.ajax(url)` 是同步语义。做法：
/// - worker：任务调用 [WorkerContext.callHost] → 请求经 SendPort 发给主 isolate → `Mailbox.take()` 阻塞当前线程；
/// - 主 isolate：[HostHandler] 用普通异步代码处理 → 结果 `put` 进 Mailbox 唤醒 worker。
///
/// 主 isolate 永远不阻塞；worker 不会永久阻塞：每个任务都有截止时间，到期按取消处理。
library;

export 'src/errors.dart';
export 'src/pool.dart' show CancelToken, HostCall, HostHandler, WorkerPool;
export 'src/worker.dart' show WorkerContext;
