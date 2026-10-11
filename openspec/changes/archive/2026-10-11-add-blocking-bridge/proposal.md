## Why

规则引擎要放在工作 isolate 里同步执行。书源 JS 里的 `java.ajax`、`java.getVerificationCode`，以及规则回调里嵌套执行的 JS，都要求「工作线程停住，等主 isolate 的异步结果」。这个阻塞桥现在只是 spike（`spike/lib/js_worker.dart`），证明了路线可行，但缺三样正式开发离不开的东西：

- **取消**：用户退出搜索或换章时，正在跑的任务停不下来。阻塞中的宿主请求停不下来，JS 死循环也停不下来。
- **调度**：一次搜索要同时请求几百个书源，spike 每次手动 spawn 一个 worker，没有并发上限。
- **生命周期**：worker 异常退出时，没有人处理它手上的任务。

下一个 change 是规则引擎，它直接建在这个桥上，所以要先把桥的接口和语义定下来。

## What Changes

- 新增纯 Dart 包 `packages/blocking_bridge`：
  - 工作 isolate 池（`WorkerPool`），并发有固定上限；worker 按需创建，任务先进先出排队，不和书源绑定。
  - 任务是一个在 worker 里同步执行的 Dart 闭包。闭包通过 `WorkerContext.current.callHost(op, payload)` 同步等待主 isolate 处理宿主请求。返回值可以是 JSON 值，也可以是原始字节。
  - 每个任务都有截止时间，到期按「取消」处理，保证 worker 不会永久阻塞。宿主处理方可以把某次请求声明为「用户交互类」（如验证码），等待用户期间截止时间暂停计时。
  - 取消用 `CancelToken`，一个 token 可以同时取消一批任务（例如一次搜索下所有书源的任务）。取消信号覆盖三种状态：排队中、阻塞在宿主请求上、正在执行。正在执行的任务通过共享内存里的中止信号感知取消。
  - 取消后调用方立即拿到结果，不等 worker 真正停下。worker 超过宽限期还停不下来，就杀掉重建。
  - 任务不管因为什么结束（取消、超时、worker 退出、池关闭），主侧都会通知它在途的宿主请求，让网络请求、弹窗可以中断。
  - worker 异常退出时，它手上的任务以错误结束，池自动补位。
- `quickjs_ng_ffi` 新增「外部中止信号」：`eval` 可以接收共享内存里的一个中止标志，QuickJS 的中断回调同时检查截止时间和这个标志。宿主函数每次返回 JS 时也检查这个标志，所以中止能穿过嵌套求值和宿主函数的边界。JS 的 `try/catch` 和中间的 Dart 代码都拦不住中止。
- `spike` 改为依赖新包，删除 `spike/lib/js_worker.dart`。原有的 11 项验证改写到新接口上，再补充取消相关的验证项，包括 JS 和桥组合在一起的端到端场景。
- 在 Android 真机上用 AOT 构建跑一遍完整验证，补上选型文档「没有验证到的部分」里的第一条。

## Capabilities

### New Capabilities
- `blocking-bridge`：工作 isolate 池，包括同步宿主调用、任务截止时间、取消、worker 故障恢复。这个能力与 JS 无关。
- `js-engine`：quickjs-ng 绑定对外承诺的行为。本次只新增「外部中止信号」，引擎的其它既有行为留到以后需要时再补规格。

### Modified Capabilities
（无。`openspec/specs/` 目前为空。）

## Impact

- 新增包：`packages/blocking_bridge`。依赖 `native_synchronization`（仓库内）和 `ffi`，不依赖 Flutter，在开发机上用 `dart test` 测试。它不依赖 `quickjs_ng_ffi`，测试也不依赖。JS 由使用方接入：现在是 spike，以后是规则引擎。
- 修改：`packages/quickjs_ng_ffi` 的 C 胶水（`src/quickjs_ng_ffi.{h,c}`）、ffigen 生成的绑定，以及 `JsEngine.eval` 的签名。新增的是可选参数，向后兼容。
- 修改：`spike/` 的验证代码和 pubspec；`README.md` 和 `packages/quickjs_ng_ffi/README.md` 里指向 `js_worker.dart` 的说明。
- 设备：真机验证需要一台 Android 真机。
