## Context

现有实现见 `spike/lib/js_worker.dart`：

- 一个 `JsWorker` 对应一个 isolate，任务是「JS 代码字符串 + 全局变量」。
- 宿主请求通过 SendPort 发给主 isolate，worker 阻塞在 `Mailbox.take()` 上；主 isolate 处理完，把 JSON 编码的结果 `put` 回去。
- 所有宿主请求共用一个 15 秒超时。`dispose` 时先 `close` Mailbox 唤醒 worker，再 kill isolate。
- Mailbox 由 worker 创建；主侧拿到的是 `materialize` 出来的副本，副本上不挂 finalizer（`mailbox.dart:64-67`）。

「SendPort 发请求 + Mailbox 回复」这条通道已在三个平台上通过 11 项验证，本次保持不变。

约束：

- 规则引擎和 JS 引擎必须在同一个 isolate 里：`java.getString("@js:...")` 和 `java.ajax` 内部的 `AnalyzeUrl` 都会在宿主回调中重新进入 JS（`docs/review/推理链复核-2026-09-26.md` 1.4 节）。所以 worker 里跑的是整条规则执行链，不只是 JS。
- Legado 每次 evalJS 都新建作用域，书源之间唯一共享的是 jsLib，由 `SharedJsScope` 按内容缓存（复核文档 1.5 节）。JS 状态不需要和某个 worker 绑定。
- QuickJS 的中断回调返回非 0 时，会抛出一个 uncatchable 错误（`quickjs.c:8647-8651`），`catch` 和 `finally` 都拦不住（`quickjs.c:20929`），正则执行期间也会检查中断（`libregexp.c:2798-2806`）。但宿主函数返回错误时，C 胶水层用的是 `JS_ThrowPlainError`（`src/quickjs_ng_ffi.c:122`），抛出的是可以被捕获的普通错误。中止要穿过宿主函数边界，就得改这里。

## Goals / Non-Goals

**Goals:**
- 用一个取消信号覆盖任务的三种状态：排队中、阻塞在宿主请求上、执行中。
- 「worker 不会永久阻塞」只靠任务截止时间这一个机制保证。
- 桥本身和 JS 无关。

**Non-Goals:**
- 优先级调度（例如正在读的章节插队到后台搜索前面）。本次只做先进先出，见风险一节。
- 书源亲和调度（把任务优先派给已加载过该书源 jsLib 的 worker）。规格明确不保证亲和，以后作为优化加入也不会改变规格。
- 回收空闲 worker。
- Windows / Linux 平台。`quickjs_ng_ffi` 目前只支持 Android、iOS、macOS。
- 接入真实的 WebView。
- 跨 worker 的书源状态一致性：Cookie、`java.put/get`、`cache.*`。任务不绑定 worker，这些状态只能经 `callHost` 去主侧读写，或者放进共享存储。具体方案由规则引擎的 change 决定，桥只提供 `callHost` 这条通道。

## Decisions

### D1 并发：固定上限的池，任务不绑定书源

一次搜索会同时打几百个书源。每个书源一个 worker，就意味着几百个 isolate 加几百个 QuickJS runtime，内存撑不住。按上面的约束，书源 JS 也没有必须留在某个 worker 里的状态：jsLib 只是缓存，在哪个 worker 上都能重建。所以真正要权衡的是内存，不是语义，选固定上限的池。

- 备选：每个书源一个 worker。没有语义上的好处，内存随书源数线性增长，排除。
- 备选：池加书源亲和。这是在本方案上做的缓存优化，等规则引擎测出 jsLib 的加载成本再决定，列为 Non-Goal。

worker 按需创建，创建后常驻。主 isolate 从不阻塞，随时可以 spawn。复核文档 3.4 节说「要在任何 JS 执行前预先 spawn 好助手 isolate」，那条限制针对的是由阻塞方自己去 spawn 的方案，这里不适用。

### D2 任务形态：在 worker 中同步执行的 Dart 闭包

接口：`pool.run<R>(R Function() task, {Duration? timeout, CancelToken? cancelToken})`。闭包和返回值通过 SendPort 在同一个 isolate group 内传递：`Isolate.spawn` 出来的 worker 与主 isolate 同属一个 group，可以传闭包。限制是闭包捕获的变量里不能有 `ReceivePort`、`Finalizable` 之类的对象（`isolate.dart:871-893`）。

- 备选：沿用 spike 的「JS 代码字符串 + globals」。这样桥只能执行 JS，规则引擎只能放在主 isolate，规则引擎在 JS 回调里被同步重新进入的那条路径就没法实现。排除。
- 备选：预先注册 worker 入口，再按消息类型分发。每加一种任务就要写一套消息类和分发代码，而闭包已经能表达同样的东西。排除。

### D3 worker 侧入口：`WorkerContext.current`

worker 侧只暴露一个 isolate 级的「当前任务上下文」，提供三样东西：
- `callHost(op, payload)`：同步宿主请求；
- `abortSignal`：本任务的中止标志，交给 `JsEngine.eval` 使用；
- `throwIfCancelled()`：供规则引擎在 JS 之外的循环里检查取消。

为什么不把上下文作为闭包参数传进去：JS 引擎会在 worker 里缓存复用，宿主函数只在引擎创建时注册一次。如果宿主函数捕获的是参数传进来的上下文，后面的任务用到的就都是第一个任务的上下文。worker 一次只执行一个任务，所以「当前任务」这个信号是准确的。

### D4 宿主请求通道

- **请求**：worker 通过 SendPort 发送 `(requestId, op, payload)`。
- **回复**：主侧往 Mailbox 里 `put` 一个二进制帧，格式为 `[类型 1 字节][requestId 4 字节][内容]`。类型有四种：JSON 值、原始字节、错误消息、已取消。worker 收到后先校验 requestId。worker 同一时刻最多只有一个在途请求，所以 requestId 不用于路由，只用来断言、发现编程错误。原始字节类型让字体、压缩包这类 MB 级数据不必经过 base64 和 JSON 转义。
- **并发请求**：`java.ajaxAll` 这类需要并发的宿主能力，做成一个宿主请求类型，由主侧并发完成，通道本身仍然一次只有一个在途请求。

**每个请求恰好回复一次。** 主侧为每个在途请求记录「是否已回复」，下面几件事谁先发生就按谁回复，之后到达的结果一律丢弃：
- 宿主处理完成；
- 所属任务因任何原因结束：取消、超时、池关闭。

请求到达主侧时，如果所属任务已经结束，立即回复「已取消」，不交给宿主处理方。这种情况发生在 worker 检查完标志、发出请求，而主侧已经先完成了取消：请求消息晚于取消到达，不立即回复的话，worker 会一直卡到宽限期被杀。

**任务结束时通知处理方。** 任务结束时，主侧把它在途请求的 `HostCall.cancelled` future 完成，处理方据此中断 dio 请求、关闭弹窗。

**不设单个宿主请求的超时**，去掉 spike 里的全局 15 秒。等多久由宿主处理方决定：网络请求用 dio 自己的超时；「worker 不会永久阻塞」由任务截止时间兜底。

**用户交互类请求。** 处理方调用 `HostCall.markInteractive()` 后，所属任务的截止时间暂停计时，到这次请求回复时再恢复。截止时间防的是机器不响应：网络卡住、JS 死循环。等用户输入的时长由界面自己约束：用户关掉弹窗，就等于取消。这两种等待不该共用一个时钟。否则一个跑了 50 秒才碰到验证码的任务，只剩 10 秒留给用户输入。

**Mailbox 的内存不变量：**
- Mailbox 由 worker 创建，并由 worker 的 isolate 级变量持有，直到 worker 退出。如果只放在局部变量里，可能在任务执行中被 GC 回收，`Finalizer` 释放内存之后，主侧再 `put` 就是 use-after-free。
- worker 退出后，Mailbox 的 native 内存有意不释放，主侧永远不 free 它。Dart 的 `Finalizer` 在 isolate 退出时不会运行（VM 的 `RunAndCleanupFinalizersOnShutdown` 只运行 `NativeFinalizer`），所以 worker 被放弃之后到收到 onExit 之前这段时间里，主侧迟到的 `put` 写进的仍是有效内存。每个退出的 worker 会泄漏大约一百字节，这是有意的取舍。
- 主侧对自己已经 `close` 过的 Mailbox 不再 `put`，由 D6 的状态机保证。

### D5 取消信号：每个任务一块共享内存中止标志

派发任务时，主侧 `malloc` 一个 `Int32`，初值为 0，把它的地址随任务一起发给 worker。取消时，主侧先写 1，再唤醒 worker：如果 worker 阻塞在宿主请求上，就 `put` 一个「已取消」回复。Mailbox 内部的互斥锁保证 worker 醒来后能读到已经写入的标志。

标志在以下几处被检查：
1. worker 发起宿主请求之前：已取消就直接抛出 `TaskCancelledException`，不发请求；
2. worker 从 `take()` 醒来后：收到「已取消」回复，就抛出 `TaskCancelledException`；
3. 执行 JS 期间：在 QuickJS 的中断回调里检查，以及宿主函数返回 JS 时检查，见 D8；
4. 规则引擎在 JS 之外的循环里，调用 `throwIfCancelled()` 检查。

**标志内存的生命周期：** 任务记录里持有一个可空的标志指针。worker 回报任务结束或 worker 退出后，主侧释放这块内存，并把指针置空。取消时只对指针非空的任务写标志。同一个令牌可能关联多个任务，再次触发时，对已释放的任务什么都不做，不会写到已释放的地址。

**截止时间**就是主侧的一个定时器，到点后以「超时」为原因走同一套取消流程。取消原因由主侧记录，所以提交方收到超时错误还是取消错误，由主侧判定，不依赖 worker 回传。

备选方案：
- 用 `Isolate.kill` 加重建来取消。kill 打断不了阻塞在 native 调用里的 isolate，也打断不了 QuickJS 的循环，还会丢掉缓存；立即 kill 在栈上有 native 帧时还会让进程崩溃（见 D6）。排除。
- 每个 worker 一个标志，在里面写「被取消的 jobId」。worker 换任务时，「重置」和「写入」之间存在竞争。每个任务各用一块内存，就不需要重置。
- 通过 SendPort 给 worker 发取消消息。worker 正阻塞着或者在同步执行，处理不了消息。排除。

### D6 取消立即返回；worker 状态机和宽限期

取消后，提交方的 future 立即以错误结束。worker 继续执行，直到它回报任务结束，这份回报会被丢弃。宽限期（暂定 2 秒）内没有回报，就**放弃**这个 worker：close 它的 Mailbox，发 `Isolate.kill(priority: beforeNextEvent)`，把它移出池的容量，然后补一个新 worker。被放弃的 worker 在当前计算返回、回到事件循环时退出。这个兜底针对的具体场景是：规则引擎在 JS 之外的 Dart 代码里卡住，标志检查不到，典型的例子是书源正则发生灾难性回溯。

**为什么不用 `Isolate.kill(priority: immediate)` 强行结束（实现中实测）**：立即 kill 会在 Dart 的检查点上拆掉 isolate。如果 worker 当时在 JS 调用的 Dart 宿主函数里，栈上夹着 QuickJS 的 C 帧，拆除过程穿不过这些帧，整个进程就会 `SIGSEGV`：读地址 `0x7`，纯 Dart 下的最小用例和 macOS 上的 spike 都复现了。目前只在 QuickJS 宿主回调（返回指针、没有 `exceptionalReturn`）上复现过，qsort 回调（返回 int、带 `exceptionalReturn`）和 twalk 回调（返回 void）上没有复现；但这正是本项目的常规路径。在这个架构里，Dart 代码被 JS 回调调用是常态，而且没有通用的方法判断此刻栈上有没有 native 帧，所以任何路径都不使用立即 kill。

代价是卡死的计算会继续占一个线程和 CPU，直到它自己结束。根本的解决办法是让耗时计算都能看到同一个中止标志，放在规则引擎里做：例如正则改走 QuickJS 的 libregexp，它执行时会检查中断（`libregexp.c:2798-2806`）。

worker 状态和事件（主 isolate 单线程处理，事件先到先得）：

| 状态 | 任务结束回报 | 宽限期到 | onExit |
|---|---|---|---|
| 启动中 | — | — | 移除 |
| 空闲 | — | — | 移除 |
| 忙 | 交付结果，转空闲 | — | 任务以 `WorkerExitedException` 结束，通知在途请求，移除 |
| 已取消、等待回报 | 丢弃结果，撤销宽限期定时器，转空闲 | 放弃：close Mailbox + `kill(beforeNextEvent)`，移出容量，转「已放弃」 | 移除 |
| 已放弃 | 释放中止标志，丢弃结果 | — | 移除 |

- 计数规则：可用的 worker 是除「已放弃」以外的所有状态，包括正在启动的。只有可用数小于上限、并且队列非空时，才 spawn 新 worker。「补位」只有这一条路径，宽限期和 onExit 不会各补一次。已放弃的 worker 单独记录，直到收到 onExit，用来释放中止标志、关闭端口。
- 池关闭：撤销所有定时器；所有执行中的任务以错误结束并写中止标志，让 JS 和阻塞中的宿主请求都退出；然后放弃所有 worker。标记池已关闭后，之后的所有事件只做清理，不再 spawn。

### D7 错误传递

| 情况 | 提交方收到 |
|---|---|
| 任务抛出异常 | 原异常对象（同一个 group 内可以传递）加栈信息字符串；对象无法传递时，退化为带原始信息的 `RemoteError` |
| 主动取消 | `TaskCancelledException` |
| 截止时间到 | `TaskTimeoutException` |
| worker 意外退出 | `WorkerExitedException` |
| 池已关闭 | `StateError` |

worker 侧：宿主处理失败时，`callHost` 抛出 `HostCallException`，任务可以捕获它；任务被取消时，抛出 `TaskCancelledException`。worker 意外退出用 `Isolate.addOnExitListener` 和 `addErrorListener` 检测。

### D8 QuickJS 中止标志

C 胶水层：
- `QjsEngine` 新增 `const int32_t *abort_flag` 字段，`qjs_eval` 增加同名参数，可以传 NULL。和 `deadline_ms` 一样，只在最外层求值时设置，退出时清空，所以嵌套求值自动用外层的标志。
- 最外层求值在调用 `JS_Eval` 之前先检查一次标志。QuickJS 的中断计数器只在循环回边和函数调用时递减，每 1 万次才调用一次中断回调（`quickjs.c:556`、`8653-8671`），没有循环的直线代码可能一次都不检查。
- `interrupt_handler` 用 `__atomic_load_n(flag, __ATOMIC_RELAXED)` 读取标志，结果和截止时间的判断取「或」。
- `host_function` 在 Dart 回调返回之后，不管回调成功还是失败，都检查一次标志。标志已设置时，不返回回调的结果，改为构造一个 Error，调用 `JS_SetUncatchableError` 后再 `JS_Throw`。

为什么用「在边界检查标志」，而不是在错误通道里新增一种「中断」错误类型：标志本身就是最准确的信号，C 侧随时能拿到。在错误通道里加一种类型，只是把同一个信息再传一遍，还要求中间每一层 Dart 代码都正确地转发它。在边界检查标志，即使下面几种情况发生，中止也照样生效：
- 中间的 Dart 宿主函数吞掉了内层的中止；
- 宿主函数在标志设置后正常返回；
- 阻塞中的 `callHost` 被「已取消」回复唤醒、抛出普通异常。

调用方的 JS 都会在宿主函数返回的那一刻被中止。

Dart 侧：签名改为 `JsEngine.eval(code, {timeout, Pointer<Int32>? abortSignal, filename})`，新参数是可选的。被中止时仍然抛 `JsException`，不新增异常类型；Dart 调用方要判断是不是被取消，直接看标志或调 `throwIfCancelled()`。两个包都依赖 `ffi`，所以直接用 `Pointer<Int32>` 作为两边共用的类型。

### D9 包结构与测试

```
packages/blocking_bridge/
  lib/blocking_bridge.dart      导出 WorkerPool、CancelToken、WorkerContext、HostCall、异常类型
  lib/src/pool.dart             主侧：队列、派发、取消、截止时间、worker 状态机
  lib/src/worker.dart           worker 侧：isolate 入口、WorkerContext、callHost
  lib/src/protocol.dart         消息类型、回复帧的编解码
  test/
```

纯 Dart 包，用 `dart test` 测试。不依赖 `quickjs_ng_ffi`，测试也不依赖。

JS 和桥组合起来的端到端场景放在 spike 里：spike 组装「池 + 引擎 + `java.*` 宿主函数」，覆盖原有 11 项验证，以及 JS 捕获不到取消、阻塞中取消、批量取消，在设备上跑集成测试。

## Risks / Trade-offs

- [先进先出：大搜索占满所有 worker 时，打开章节要排队] → 池对象很轻，规则引擎的 change 可以给「阅读」单独开一个小池，和「搜索」分开，不用改本包；确实需要优先级时再加到队列上。
- [闭包捕获了不能跨 isolate 传递的对象] → 提交时 `send` 就会抛错，规格要求提交方收到错误。包文档里写明闭包的约束，以及过度捕获的问题（dartbug 36983）。
- [被放弃的 worker 卡在不检查中止标志的计算里，会一直占用一个线程和 CPU，直到计算结束] → 池容量会立即补回来，提交方也已经拿到错误；根本解决放在规则引擎，让耗时计算都检查同一个中止标志（见 D6）。强行结束会导致进程崩溃，两害相权取其轻。
- [规则引擎的 Dart 代码吞掉 `TaskCancelledException` 继续执行] → 下一次碰到桥（`callHost`、`eval`、`throwIfCancelled`）时还会再失败；结果反正会被丢弃，宽限期是最后的兜底。包文档写明不要吞取消异常。
- [worker 侧在 Dart 里读标志是普通 load：实现中实测，`while (!isCancelled) {}` 内联后，JIT 把这次读取提到了循环外，永远读不到取消] → `isCancelled` 加 `@pragma('vm:never-inline')`，每次检查都是一次真实的调用和读取。已在 JIT（单元测试）和 AOT（`dart compile exe`）下验证。Dart 代码只通过 `isCancelled` / `throwIfCancelled` 读标志，不要直接读 `abortSignal`。
- [主侧写标志用的是普通的 `Pointer<Int32>.value` 存储] → 在所有目标 ABI（arm64、armv7、x86_64）上，对齐的 32 位存储是单拷贝原子的，C 侧用 atomic load 读取。这一点目前按架构常识判断，没有逐条查手册核实。

## Migration Plan

- 删除 `spike/lib/js_worker.dart`，spike 改为依赖新包。spike 不是产品代码，不需要回滚方案。
- `JsEngine.eval` 新增的是可选参数，现有调用不受影响。

## Open Questions

- ~~**默认 worker 数**~~：定为 4（2026-10-11）。真机 AOT 实测每个 worker 空闲约 0.7MB，跑完约 1MB 数据的 JS 后约 1 到 3MB，内存不构成约束；上限主要看 CPU 核数和同时发出的网络请求数。
- **默认截止时间和宽限期**：暂定 60 秒和 2 秒。等待用户输入的时间不计入截止时间，见 D4。
