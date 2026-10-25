## 1. 引擎：分段搜索（packages/rule_engine）

- [x] 1.1 `HandleTable.clear()`：清空登记的对象和 id 映射（D2）。验证：在 1.2 的测试里覆盖：第二段登记书源时，拿到的是新 id，并且能取回书源。
- [x] 1.2 `chains.dart`（D2）：
  - 新增 `SearchStep`、`prepareSearch`、`finishSearch`，两段都包在 `_withTask` 里
  - 第一段结束时清空 `task.handles`
  - `searchBooks` 改为 prepare → checkCancelled → `env.fetch` → finish
  - `rule_engine.dart` 导出新的 API

  验证：`dart test` 全部通过，`chains_test`、`chains_js_test`、`recorded_test` 不用改。
- [x] 1.3 `tasks.dart` 新增顶层任务工厂 `prepareSearchTask(source, key)`、`finishSearchTask(step, result)`。验证：在 2.2 的测试里用真实的池跑通。

## 2. 引擎测试

- [x] 2.1 `chains_test.dart`（FakeEnvironment）新增分段用例，对应 book-chains「分段搜索」：
  - 「地址里的 JS 只执行一次」：`java.log` 只有一条
  - 「第二段执行 loginCheckJs」：第一次响应含「请登录」时，第二段重发同一个请求，按第二次响应解析
  - 列表规则出错时，两段执行的错误带着和一次执行相同的书源名和字段

  验证：新用例通过。
- [x] 2.2 `chains_worker_test.dart`：用真实的 `WorkerPool`，第一段的结果经主 isolate 交给第二段，主 isolate 用假的网络回复，结果和一次执行 `searchTask` 相同。对应「两段执行和一次执行结果相同」，同时验证 `SearchStep` 能跨 isolate 传递。验证：新用例通过。
- [x] 2.3 `recorded_test.dart`：对每个录制样例，用回放环境分别一次执行、分两段执行搜索，两者的结果和日志都相同（D2 风险项，覆盖 jsLib、请求头 JS、`bodyJs` 等真实书源写法）。验证：全部样例通过。

## 3. app：搜索编排（app/lib/online/）

- [x] 3.1 `Batch` 新增 `stopped` future，`stop()` 时完成（D6）。验证：`batch_test.dart` 新增用例：stop 之后 `stopped` 完成；重复 stop 不报错。
- [x] 3.2 `PoolSourceEngine.search` 改成三步（D3、D4、D5）：
  - 第一段、第二段经批量限流器（4），网络这一步经独立的网络限流器（32）
  - 构造参数新增请求函数，以及可注入的单书源超时（默认 30 秒，测试里注入短的）
  - 网络失败时包成 `HostCallException('$error')`，并且不提交第二段
  - 三步无论哪一步超时，都抛 `TaskTimeoutException(单书源超时)`
  - 停止时网络这一步立即以取消结束

  `engine_stack.dart` 和 `startup.dart` 把 `host.execute` 传进来。验证：`flutter analyze` 通过，3.3 的测试通过。
- [x] 3.3 新建 `test/online/source_engine_test.dart`：真实的 `WorkerPool`，配假的请求函数，覆盖：
  - 12 个书源，每个响应要 2 秒，4 秒内全部完成（book-search「多个慢书源同时等待」）
  - 40 个书源同时搜，同时在途的请求最多 32 个
  - 注入 1 秒超时、响应要 3 秒的书源以 `TaskTimeoutException(1 秒)` 结束，其它书源不受影响（「慢的书源按超时失败」，按比例缩短时间）
  - 请求失败时的错误是 `HostCallException`，消息和原始异常的 `toString()` 相同，并且没有提交第二段
  - 停止后，等网络的书源在 100 毫秒内以取消结束

  验证：新用例通过。
- [x] 3.4 `describeError` 对 `TaskTimeoutException(30 秒)` 显示「超时：超过 30 秒」。验证：`search_controller_test.dart` 和 `search_page_test.dart` 通过；如果已有用例写死了 60 秒，改成 30 秒。

## 4. 计时报告

- [x] 4.1 `integration_test/real_sources_test.dart` 的「在 200 个书源上搜索一次」每次 pump 时记录已完成数和失败数的变化，`REPORT` 里加上（D7）：
  - 完成一半、九成、全部书源时各用了多少秒
  - 30 秒以后才完成的书源里，成功几个、失败几个

  验证：用 `WALKTHROUGH_SOURCES` 的 14 个书源先跑一次，报告格式正确。

## 5. 验收

- [x] 5.1 准备书源文件：从 aoaostar/legado 下载 `sources/b778fe6b.json`，按以前的脚本（文本类、有搜索地址，`random.seed(1)` 抽 200 个，全部启用）生成 `random200.json`，用本地 HTTP 服务器提供。需要能访问 GitHub：这台机器现在连不上，到这一步时先找你开代理，或者请你提供文件。验证：文件里有 200 个书源，去重后的数量和以前的 192 接近。
- [x] 5.2 校准超时：临时把单书源超时改成 60 秒，在 macOS 上跑一次计时，看 30 秒以后才成功的书源有几个（D4）。验证：把数字记进 design.md D4。如果不是个别几个，暂停，和你讨论超时的取值。跑完把超时改回 30 秒。
- [x] 5.3 在 macOS、iOS 模拟器、Android 模拟器（emulator-5554）上各跑一次 200 个书源的计时。验证：
  - 三端总耗时都在 60 秒以内
  - 有结果的书源数不比以前（118 到 123）少很多，失败原因的分布和以前相近，只是多了「超时」这一类
- [x] 5.4 回归：
  - `packages/rule_engine`、`packages/blocking_bridge` 跑 `dart test`
  - `app` 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，并跑 `flutter analyze`
  - `integration_test/app_flow_test.dart` 在 `-d macos` 和 `-d emulator-5554` 上跑
  - 走查 `real_sources_test.dart` 的 A、C 类书源至少在 macOS 上跑一次

  验证：全部通过。

## 6. 文档

- [x] 6.1 PRD：
  - 4.2 节「搜索提速」改为已完成，说明写上新的计时
  - 第六节「随机 200 个书源搜一次」后面括号里的现状更新
  - 第七节第 4 步标为已完成
  - 真机测试的注意事项里加上「同时 32 个连接在手机网络上的表现」

  验证：通读一遍，和实现一致。
- [x] 6.2 选型文档第 152 行（搜索计时）后面补一段：分段搜索之后三端的耗时，以及「网络等待不占 worker」这个结论。原来的「要再快应该缩短搜索的超时」改成指向这次的 change。验证：通读一遍，和实现一致。
