## Context

动机和范围见 proposal.md，行为要求见 specs/book-search/spec.md 和 specs/book-chains/spec.md。

### 现状

- **一个书源的搜索**是一个 worker 任务：`PoolSourceEngine.search` → `BatchLimiter`（批量任务同时最多 4 个）→ `WorkerPool.run(searchTask(...))`。任务里 `searchBooks` 依次做三件事：
  1. 构造请求（`buildSourceRequest`，地址里的 JS、请求头 JS）。
  2. `_fetch`：`env.fetch` 经阻塞桥交给主 isolate 的 `RuleHost.execute`，worker 在 `Mailbox.take()` 里等结果；然后执行 `bodyJs`、`loginCheckJs`。
  3. `_analyzeBookList` 解析列表。
- **超时**：
  - 任务截止时间 60 秒，从任务开始执行算起，等网络的时间也算在内。
  - `RuleHost` 的连接超时 15 秒，单次请求超时 60 秒。
- **worker 上限 6**：阻塞在 `Mailbox.take()` 里的 worker 照样占着 Dart VM 的 mutator 名额（选型文档）。
- **JS 作用域**：`SourceJs` 每次求值都新建一层作用域（`JsLayer`），求值之间只共享按 MD5 缓存的 jsLib。一个任务里前后两次求值，本来就不共享 JS 变量。
- **`HandleTable`**：交给 JS 的 Dart 对象（书源、元素、响应）登记在任务的 `SourceTask.handles` 里。id 来自一个 isolate 级的静态计数器，每个 worker 各数各的。

## Goals / Non-Goals

**Goals:**
- worker 只用来执行书源规则，等网络时不占 worker。
- 两段执行和一次执行可以逐项对照，不需要靠「请求相同就复用」之类的猜测。
- `searchBooks` 一次执行的路径保留：冒烟工具、回放测试、已有测试都不用改。

**Non-Goals:**
- 把整个引擎改成异步，或者让其它链路也分段。
- 第二段里 `loginCheckJs` 调 `java.getStrResponse()` 重发请求、地址 JS 里调 `java.ajax` 这类请求不再优化，仍然在 worker 里阻塞等待。随机抽样里这类书源很少。

## Decisions

### D1 根因：worker 被网络等待占着，所以把网络等待移出 worker

一次搜索的总耗时 ≈ 所有书源占用 worker 的时间之和 ÷ 同时可用的 worker 数。proposal 里的历史计时显示，总耗时和并发数几乎成反比，所以占用时间的大头是等网络，不是计算。

真正有限的资源是 worker，也就是 mutator 名额，它是给计算用的；等网络本身不需要 worker。所以要做的是让「等网络」不占 worker。

考虑过的方案：

| 方案 | 结论 |
|---|---|
| 只缩短超时 | 所有书源的占用时间加起来约 576 worker·秒，其中有结果的书源就要占二百多。即使失效的书源一秒不占，分给 4 个 worker 仍要 60 秒左右，到不了目标，还会误伤慢但可用的书源。 |
| 按历史响应时间排序、跳过失效书源 | 排序只改变谁先出结果，不减少占用时间的总和。跳过会让临时连不上的书源永远搜不到，还要维护一套书源健康状态。 |
| 加 worker | 不行，上限是 Dart VM 定的（选型文档：8 个已经明显变慢，16 个会卡死）。 |
| 主 isolate 先按构造好的请求预取，worker 里遇到相同请求时直接用预取的结果 | 构造请求要跑两遍：地址里的 JS 执行两次，`java.log` 写两条，书源变量写两次。请求带时间戳或随机数时匹配不上，又会退回慢路径。 |
| **分两段执行，中间由主 isolate 发请求（采用）** | 每一步只执行一次，行为和一次执行一一对应。 |

### D2 引擎里的拆分

`chains.dart` 新增：

```dart
/// 分段搜索的第一段结果：构造好的请求，和第二段需要的状态。
final class SearchStep {
  HttpRequest get http;          // 交给提交方发出的请求
  // 内部持有：SourceRequest（含 SourceTask）、ChainData
}

SearchStep prepareSearch(RuleEnvironment env, BookSource source, String key, {int page = 1});
List<SearchBook> finishSearch(SearchStep step, HttpResult result);
```

- `searchBooks` 改为 `prepareSearch` → `checkCancelled` → `env.fetch(step.http)` → `finishSearch`，和现在的顺序完全一样。一次执行的路径不变。
- 第二段从 `SourceRequest.response(result)` 开始，处理 `type`、`bodyJs`，再执行 `loginCheckJs`，然后 `_analyzeBookList`。这些就是现在 `_fetch(loginCheck: true)` 拿到响应之后做的事。
- 两段都包在 `_withTask` 里，错误照样补上书源名和字段。第二段的默认字段要和一次执行时一样。
- `tasks.dart` 新增 `prepareSearchTask(source, key)` 和 `finishSearchTask(step, result)` 两个任务工厂，也是顶层函数。
- **第一段结束时清空 `task.handles`**：
  - 这是规格里「随任务结束失效」的语义，第一段的 JS 作用域已经全部释放，不会再有人用这些 id。
  - 必须清空。如果把登记过的表原样带到另一个 worker，新登记的对象会从那个 worker 自己的计数器取 id，可能和表里的旧 id 相同，把旧条目覆盖掉。之后第二段再登记书源（`_sourceTag`），会从 `_ids` 查到旧 id，而这个 id 现在指向另一个对象。
  - 为此给 `HandleTable` 加一个 `clear()`。
- **跨 isolate 传递**：`SearchStep` 里都是普通 Dart 对象：书源 JSON、请求头、`ChainData` 的变量表，`SourceTask.env` 是 const 的 `WorkerRuleEnvironment`。所有 worker 都在同一个 isolate group 里，可以直接传。传不了的话，`_report` 会把它变成 `RemoteError`，测试能发现。

### D3 app 里的编排

`PoolSourceEngine.search` 改成三步，每一步各自排队：

1. 经批量限流器（4）提交 `prepareSearchTask`。
2. 经网络限流器（32）调用 `RuleHost.execute(step.http)`。
3. 经批量限流器（4）提交 `finishSearchTask`。

- 网络限流器复用 `BatchLimiter` 类，单独一个实例。`Batch.stop()` 已经能让两种限流器里排队的任务以取消结束。
- `PoolSourceEngine` 的构造参数加上请求函数 `Future<HttpResult> Function(HttpRequest, {Future<void>? cancelled})`。app 里传 `host.execute`，测试里传假的。`EngineStack` 已经同时持有 host 和 pool，在 `startup.dart` 里组装。
- **网络失败时的错误原因**：现在请求失败时，阻塞桥用 `'$error'` 构造 `HostCallException`，界面显示「网络错误：…」。主 isolate 上直接拿到的是原始异常（`SocketException` 等），这里同样包成 `HostCallException('$error')`，失败原因的文字和一次执行时一样。请求失败就不再提交第二段。

### D4 30 秒的超时怎么算

- **计时**：每个书源有 30 秒预算，只在三步执行时扣减，在限流器里排队的时间不算，和现在「从任务开始执行时计时」的口径一致。
  - 第一段、第二段用 `WorkerPool.run(timeout: 剩余预算)`。
  - 网络这一步：请求和「剩余预算到期」比谁先到。到期时通过 `cancelled` 关掉连接。
- **错误**：三步无论哪一步超时，都统一抛 `TaskTimeoutException(30 秒)`，界面显示「超时：超过 30 秒」，而不是某一步当时剩余的秒数。
- **为什么是 30 秒**：
  - 等网络不占 worker 以后，总耗时 ≈ 最慢的书源的耗时，加上第一段、第二段的计算时间。所以单书源超时直接决定最坏的总耗时。
  - 目标是 60 秒，30 秒留出一倍余量，给计算和第二段的排队。
  - 连接超时 15 秒仍然放得下。
  - 历史上并发 14 时总耗时是 51 秒，说明大部分书源在 50 秒以内完成。30 到 60 秒之间才成功的书源有多少，由任务 5.2 实测：先用 60 秒跑一次，统计 30 秒以后才成功的书源。如果不是个别几个，回来重新讨论这个数字。
  - 实测（任务 5.2，2026-10-25，macOS，单书源超时临时改成 60 秒）：192 个书源 29.6 秒全部结束，完成一半 6.6 秒、九成 15.1 秒；30 秒以后完成的书源 0 个（成功 0、失败 0）。有结果的书源 119 个，失败 73 个（网络错误 59、需要 WebView 6、JS 错误 5、规则错误 3）。30 秒不会误伤这批书源。

### D5 网络并发上限 32

- **为什么要有上限**：每个请求一个 `HttpClient`，各占一个 socket。macOS、iOS 进程默认的文件描述符软上限是 256，数据库文件、图片等也要占。用户启用上千个书源时，不加上限会耗尽描述符。
- **为什么是 32**：
  - 所有书源加起来约 576 worker·秒，按 32 路并发约 18 秒，小于 30 秒的预算，所以总耗时仍然由单书源超时决定，不由上限决定。
  - 32 离 256 还远。
- 规格只要求「至少 32」，以后真机测试时可以往上调。

### D6 停止搜索时中断网络等待

- `Batch` 加一个 `stopped` future，`stop()` 时完成。
- 网络这一步把 `stopped` 也传给 `cancelled`（和预算到期合在一起），并且和请求比谁先到：
  - 停止时立即以 `TaskCancelledException` 结束。
  - 不等 `RateLimiter.acquire` 或关连接的过程返回。
- `SearchController` 原来就按代号丢弃旧结果，也会忽略取消错误，不用改。

### D7 计时报告

`real_sources_test.dart` 的「在 200 个书源上搜索一次」每次 pump 时记录已完成数和失败数的变化，额外报告：

- 完成一半、九成、全部书源时各用了多少秒。
- 30 秒以后才完成的书源里，成功几个、失败几个。

只改测试，不改 `SearchState`。

## Risks / Trade-offs

- **[jsLib 里的可变全局变量在两段之间不共享]** 两段可能落在不同的 worker 上。不过现在同一个书源的不同任务本来就可能落在不同 worker 上，jsLib 的全局状态本来就不能跨任务依赖。地址 JS 要传给解析规则的值，走的是 `java.put` / `ChainData`，这部分会随 `SearchStep` 一起带过去。→ 用回放样例对照两段和一次执行的结果（任务 2.3）。
- **[`SearchStep` 里有对象传不过去]** → `chains_worker_test` 用真实的池跑两段，传不过去会是 `RemoteError`，测试直接失败。
- **[同时 32 个连接在手机网络上的表现]** 模拟器上测不出来。→ 记进 PRD 的真机测试项，上限是一个常量，可以调整。
- **[30 秒误伤慢书源]** → 任务 5.2 实测。界面上失败原因写明「超时：超过 30 秒」，用户能看到原因。
- **[批量限流器只有 4 个名额，第二段可能要排队]** 192 个响应在几十秒里陆续到达，每个第二段只要几十毫秒，排队时间可以忽略；而且排队不扣预算。

## Migration Plan

不涉及数据和接口迁移。回滚就是 revert 这次提交。
