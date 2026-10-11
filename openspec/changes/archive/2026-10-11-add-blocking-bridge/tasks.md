## 1. quickjs_ng_ffi：外部中止信号

- [x] 1.1 C 胶水层：
  - `QjsEngine` 新增 `abort_flag` 字段；
  - `qjs_eval` 新增参数 `const int32_t *abort_flag`，只在最外层设置和清空，调用 `JS_Eval` 之前先检查一次；
  - `interrupt_handler` 用 atomic load 读取标志；
  - `host_function` 在 Dart 回调返回后检查标志，已设置就抛出 uncatchable Error。

  验证：`./tool/build_host.sh` 编译通过。
- [x] 1.2 运行 `dart run ffigen --config ffigen.yaml` 重新生成绑定，给 `JsEngine.eval` 加可选参数 `Pointer<Int32>? abortSignal`。验证：原有 8 项单元测试全部通过。
- [x] 1.3 为 `specs/js-engine/spec.md` 的 6 个场景补单元测试。在执行中设置标志的方法是：另起一个 isolate，拿到标志的地址后延时写入（`eval` 是同步 FFI 调用，同一个 isolate 里的 Timer 在求值期间不会触发）。验证：`QUICKJS_NG_FFI_LIB=... dart test` 全部通过。

## 2. blocking_bridge：包骨架与通道

- [x] 2.1 新建纯 Dart 包 `packages/blocking_bridge`，依赖 `native_synchronization` 和 `ffi`，dev_dependency 只有 `test`；文件结构按设计 D9。验证：`dart pub get` 和 `dart analyze` 无错误。
- [x] 2.2 `protocol.dart`：
  - 定义两侧之间的消息：就绪、任务、任务结束回报、宿主请求；
  - 实现回复帧 `[类型][requestId][内容]` 的编解码，类型有四种：JSON 值、原始字节、错误、已取消。

  验证：编解码单元测试通过，包括 1MB 字节原样往返。
- [x] 2.3 `worker.dart`：
  - isolate 入口，用 isolate 级变量持有 Mailbox；
  - `WorkerContext.current`；
  - `callHost`：发请求前检查标志；醒来后校验 requestId，再按回复类型返回结果或抛出 `HostCallException` / `TaskCancelledException`；
  - `throwIfCancelled`；
  - 用 `try/finally` 设置和清空当前上下文，执行闭包，回报结果。

  验证：随 3.x 的测试一起通过。

## 3. blocking_bridge：池与宿主请求

- [x] 3.1 `pool.dart`：
  - 构造：`WorkerPool(size, hostHandler, defaultTimeout, cancelGracePeriod)`；
  - 按设计 D6 实现 worker 状态机、存活计数和唯一的补位路径；
  - 任务先进先出排队；任务异常原样传回。

  验证：「在工作 isolate 中执行任务」「并发上限与排队」「worker 内状态在任务间保留」的场景测试全部通过。
- [x] 3.2 主侧处理宿主请求：
  - 调用 `hostHandler(HostCall)`；
  - 每个请求按「先到先得」恰好回复一次，处理方抛异常就回复错误；
  - 所属任务已结束的请求，立即回复「已取消」，不交给处理方；
  - `HostCall.markInteractive()` 暂停截止时间，回复时恢复。

  验证：「同步等待主 isolate 的宿主请求」的 5 个场景、「任务截止时间」的「等待用户时暂停计时」场景测试通过。「请求晚于取消到达」场景的构造方法：任务发出请求后，主 isolate 先同步 sleep，让请求留在端口里，再取消；这样取消一定先于请求被处理。
- [x] 3.3 worker 退出检测：onExit / onError 监听接入状态机。验证：「worker 异常退出」场景测试通过，在纯 Dart 任务闭包里调用 `Isolate.exit()` 来模拟退出。

## 4. blocking_bridge：取消与截止时间

- [x] 4.1 实现 `CancelToken`，以及每个任务的中止标志：
  - 标志在派发时分配；
  - worker 回报结束或退出后才释放，释放后指针置空；
  - 只对指针非空的任务写标志；
  - 排队中的任务被取消时，直接移出队列。

  验证：「一次取消一批任务」「对已完成的任务取消」场景测试通过；同一个令牌在部分任务结束后再次触发，不会出错。
- [x] 4.2 取消执行中的任务：
  - 先写标志，再对在途请求回复「已取消」；
  - 提交方立即收到取消错误；
  - worker 进入「已取消、等待回报」状态；
  - 任务结束时，通知所有在途请求。

  验证：「取消阻塞中的任务」「取消正在执行的任务」「任务结束时通知在途宿主请求」「被取消的任务不再发起宿主请求」的场景测试通过。
- [x] 4.3 截止时间：主侧定时器到点后，以超时为原因走取消流程。验证：「宿主请求超过截止时间」「计算超过截止时间」场景测试通过，并且错误类型与主动取消不同。
- [x] 4.4 宽限期兜底：到期后放弃 worker，即 close Mailbox、`kill(beforeNextEvent)`、移出容量并立即补位，被放弃的 worker 在计算结束后退出；所有路径都不使用立即 kill。验证：「停不下来的 worker 被替换」的两个场景测试通过，测试中全程记录可用 worker 数的峰值；新增一项测试：worker 正在执行 JS 调用的 Dart 宿主函数时关闭池或放弃它，进程不崩溃。
- [x] 4.5 关闭池：撤销所有定时器；所有任务以错误结束，通知所有在途请求，并写中止标志；然后放弃所有 worker；之后提交立即失败，不再创建 worker。验证：「关闭池」的两个场景和「关闭时通知处理方」场景测试通过。

## 5. spike 迁移与设备验证

- [x] 5.1 spike 改为依赖 `blocking_bridge`，删除 `spike/lib/js_worker.dart`：
  - 在 `spike_checks.dart` 里组装「池 + 引擎（传入 `abortSignal`）+ `java.ajax` / `java.getVerificationCode` / `java.getString`」，其中验证码请求调用 `markInteractive()`；
  - 把原有 11 项改写到新接口上；
  - 新增 4 项：JS 死循环被取消、阻塞中的 `java.ajax` 被取消后外层 `try/catch` 拦不住、批量取消、嵌套 `java.getString` 里的取消穿透到外层。

  验证：`flutter test integration_test -d macos` 全部通过。
- [x] 5.2 在 Android 16 模拟器和 iOS 26 模拟器上跑集成测试。验证：两个平台全部通过。
- [x] 5.3 Android 真机 AOT 验证：
  - 用 `flutter drive --profile` 跑集成测试。integration_test 不支持纯 release 模式，profile 同样是 AOT 编译，并且保留了读取测试结果需要的 VM service；
  - 同时记录 4 个 worker 时每个 worker 的 RSS 增量，据此确定默认 worker 数。

  验证：真机全部通过，RSS 数据写入文档。需要接一台 Android 真机。

## 6. 文档

- [x] 6.1 文档更新：
  - 新增 `packages/blocking_bridge/README.md`，写清用法、闭包的约束、不要吞取消异常、不要在 Dart 里自旋读标志、Mailbox 内存不变量；
  - 更新根目录 `README.md` 的目录表和运行验证命令；
  - 更新 `packages/quickjs_ng_ffi/README.md`，改为指向新包；
  - `docs/技术选型与验证-2026-09-28.md`：在验证表里补上取消相关的验证项和真机结果，并把「下一步」的第 1、2 条标为已完成。

  验证：`grep -r js_worker` 在文档和代码里都没有结果。
