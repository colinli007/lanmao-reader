# blocking_bridge

阻塞桥：任务在后台 worker isolate 里同步执行，执行中可以同步等待主 isolate 的异步结果（网络、WebView、用户输入）。书源 JS 的 `var html = java.ajax(url)` 就是靠它实现的。

纯 Dart 包，与 JS 无关；JS 引擎由使用方接入（见 `spike/lib/js_tasks.dart`）。行为规格见 `openspec/specs/blocking-bridge/spec.md`，设计依据见 `openspec/changes/archive/2026-10-11-add-blocking-bridge/design.md`。

## 用法

```dart
// 主 isolate：宿主请求用普通异步代码处理
final pool = WorkerPool((call) async {
  switch (call.op) { ... }                 // call.payload 是参数
  call.cancelled.then((_) => ...);         // 任务结束（取消、超时、关池）时中断请求
  call.markInteractive();                  // 等用户输入期间，任务截止时间暂停计时
  return value;                            // JSON 值，或 Uint8List（按原始字节传给任务）
}, size: 4);

final token = CancelToken();               // 一个令牌可以取消一批任务
final result = await pool.run(searchTask(source, key), timeout: const Duration(seconds: 30), cancelToken: token);

// worker 里：任务同步等待主 isolate
Object? Function() searchTask(Source source, String key) => () {
  final html = WorkerContext.current.callHost('http.get', [url]);   // 阻塞到主 isolate 回复
  WorkerContext.current.throwIfCancelled();                         // 长循环里检查取消
  return engine.eval(code, abortSignal: WorkerContext.current.abortSignal);
};
```

## 约束

- **任务闭包要能跨 isolate 传递。** 不能捕获 `ReceivePort`、`WorkerPool` 这类对象。Dart 闭包会捕获整个外层上下文（dartbug 36983），所以任务都用顶层函数构造，例如上面的 `searchTask`。
- **跨任务复用的代码通过 `WorkerContext.current` 取上下文。** 例如 JS 引擎的宿主函数只在创建引擎时注册一次，不能捕获某个任务的上下文。
- **不要吞掉 `TaskCancelledException`。** 吞掉了也只能继续执行到下一次碰到桥（`callHost`、`eval`、`throwIfCancelled`）为止，而且结果会被丢弃。
- **Dart 代码只通过 `isCancelled` / `throwIfCancelled` 读取消标志，不要直接读 `abortSignal`。** 直接读的话，VM 可能把读取提到循环外面，永远读不到取消。
- **耗时计算要能检查中止标志。** worker 卡在不检查标志的计算里时，宽限期过后池会放弃它，补一个新 worker，但不会强行结束它：worker 的栈上可能有 native 帧（JS 调用的 Dart 宿主函数），立即 kill 会让整个进程崩溃。被放弃的 worker 会一直占着线程和 CPU，直到这段计算结束。

## 内存不变量

worker 的 Mailbox 由 isolate 级变量持有到 worker 退出。worker 退出时，Dart 的 `Finalizer` 不运行，这块 native 内存（约一百字节）有意不释放，主侧也从不释放它，这样主侧迟到的 `put` 才是安全的。不要「修复」这个泄漏。

## 测试

```bash
dart test
```
