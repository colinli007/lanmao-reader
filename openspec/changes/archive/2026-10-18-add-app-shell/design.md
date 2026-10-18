## Context

动机和范围见 proposal.md，行为要求见 specs/。

现状和约束：

- **rule_engine**：主 isolate 上建一个 `RuleHost`（网络、Cookie、限速、书源级状态），交给 `WorkerPool(host.handle)`；`searchTask`、`bookInfoTask`、`chapterListTask`、`contentTask` 交给 `pool.run`，可以带 `CancelToken` 和截止时间（默认 60 秒）。`SearchBook`、`Book`、`BookChapter` 是可变的普通对象，带着 `variables`，跨 isolate 传的是副本；目录任务把更新过的书籍一起交回。错误都继承 `RuleEngineException`。
- **书源级状态接口是同步的**：`SourceStore.get/put/delete` 在主 isolate 上同步执行（worker 通过宿主请求读写，主 isolate 处理时直接返回值）。落盘实现不能在 `get` 里等数据库。
- **Cookie**：`CookieStore` 是 `RuleHost` 里 `final` 的内存对象，持久 Cookie 和会话 Cookie 分开存；外部没有办法载入初始值，也收不到变更。
- **书源 JSON 只读**：`BookSource.json` 是导入时的原始对象（book-source 规格要求导出与导入一致），引擎不认 `enabled` 字段。
- **平台**：quickjs_ng_ffi 已在 macOS、iOS 模拟器上验证；网络走 `dart:io`，不受 ATS 限制。Flutter 3.32.4，Dart 3.8。
- **书源日志**：`SourceLog` 只带书源地址、字段和内容，由 `RuleHost.onLog` 在主 isolate 上交出。

## Goals / Non-Goals

**Goals:**
- 书源相关的代码集中在一个目录里，书架、阅读器、存储层不依赖 rule_engine，以后建 store flavor 时只替换这一层。
- 一次运行里，引擎看到的书源级状态和 Cookie 就是内存里的那一份；落盘只是它的镜像，不引入第二个真相。
- 阅读进度用与排版无关的坐标保存，换字号、换窗口大小、以后换成分页排版都能定位。
- 批量任务（搜索、书架更新）不挤占阅读和详情。

**Non-Goals:**
- 分页排版、翻页动画、标点避头尾（下一个 change）。
- Android（本次只建 iOS、macOS 工程）、store flavor、本地书（txt、epub）。
- 搜索翻页、精准搜索开关、换源（书架上的书换书源）、书源分组、书源排序编辑、书源校验。
- 发现页、登录界面、验证码、WebView 书源、界面类宿主 API（仍按 rule_engine 的规格报错）。
- 封面请求带书源请求头（MD3 会带）：本次封面用普通图片请求，取不到显示占位。
- 正文图片、替换净化规则、简繁转换、听书。
- 登录信息加密（MD3 用 androidId 加密）。

## Decisions

### D1 项目结构与模块边界

```
app/                      Flutter 项目 novel_reader（iOS、macOS）
└── lib/
    ├── main.dart         启动：打开数据库，清理不在书架上的书，载入书源级状态和 Cookie，建 RuleHost 和 WorkerPool，runApp
    ├── app.dart          MaterialApp（Material 3，跟随系统亮暗），首页是书架
    ├── storage/          drift 数据库、表、读写方法；表生成的数据类（ShelfBook、TocChapter 等）就是书架和阅读器的模型；不 import rule_engine
    ├── library/          BookContentSource 接口、书架和阅读器共用的小件（封面、当前章节重新定位）
    ├── bookshelf/        书架页
    ├── reader/           阅读页、正文排版、阅读设置
    └── online/           书源模块：引擎接入、书源管理、书源日志、搜索、详情与目录、BookContentSource 的实现
```

- `package:rule_engine` 只允许在 `online/` 里 import，用一条测试检查（扫描 `lib/` 下其它目录的 import）。
- 书架和阅读器只认 `storage/` 的模型。取目录和正文通过 `BookContentSource` 接口（`refreshShelf(books)`、`loadContent(book, chapter, next)`），由 `online/` 实现；失败统一为带原因文本的 `ContentLoadException`，阅读器不需要认识引擎的错误类型。store flavor 以后换一个实现（或不提供在线更新）即可。
- 引擎专用的数据（书籍和章节的 `variables`、`tocUrl`、`baseUrl`、`reverseToc`、`customIntro` 等）在模型里是一个不透明的 JSON 文本字段 `sourceData`，只有 `online/` 解读它。搜索和详情保存的页面（`infoHtml`、`tocHtml`）不落盘：书架更新目录时必须重新请求，才能看到新章节。书架、阅读器、存储层不需要知道这些字段。
- 导航用 `Navigator` 和 `MaterialPageRoute`，不引入路由库。首页是书架，AppBar 上有搜索和书源管理两个入口；搜索是单独压栈的页面，离开即取消（book-search 的「停止与取消」）。不用底部导航，因为切 tab 不应该等于「离开搜索」。
- 状态管理用 `flutter_riverpod`，手写 provider，不用代码生成（drift 已经要跑 build_runner，再加 riverpod_generator 收益不大）。

备选：把 rule_engine 的模型直接用作书架模型。少一层转换，但书架、阅读器、存储都会依赖引擎，store flavor 就做不成「不带书源模块」。转换只在 `online/` 一处，成本可控。

### D2 存储：drift（SQLite），一个数据库装下全部数据

选型文档定的是 drift 加 hive_ce（键值）。本次的键值数据只有阅读设置和书源级状态：书源级状态带过期时间，设置只有几项，放进 SQLite 的两张表就够了，不再引入 hive_ce。这样所有数据在一个事务边界里，「移出书架时清理」「加入书架」都是一个事务。

表（主键加粗）：

| 表 | 列 |
|---|---|
| `sources` | **url**、json（导入时的原始文本）、enabled、position（首次导入的顺序） |
| `books` | **book_url**、origin、origin_name、name、author、kind、cover_url、intro、word_count、latest_chapter_title、dur_chapter_index、dur_chapter_url、dur_chapter_title、dur_chapter_pos、in_shelf、added_at、last_read_at、source_data |
| `chapters` | **book_url, idx**、url、title、is_volume、is_vip、is_pay、tag、source_data |
| `contents` | **book_url, chapter_url**、title、content |
| `source_kv` | **key**、value、deadline（可空） |
| `cookies` | **domain**、cookie（只存持久 Cookie） |
| `settings` | **key**、value |

- 书的主键是书籍地址，与 MD3 一致；详情页判断「已在书架」也用它。
- 章节数、未读章节数不存列，查询时从 `chapters` 数（未读是排在当前章节之后的非卷章节）。最新章节名取目录的最后一章（MD3 的 BookChapterList），引擎的目录链路不改它。
- 正文缓存放在 SQLite 里，不写文件：一章约 10KB，2000 章约 20MB，可以接受；删除书时一条语句带走，不会留下孤立文件。
- 数据库用 drift 的后台 isolate 打开（`driftDatabase` / `createInBackground`），查询不阻塞界面。

### D3 不在书架上的书：同一条存储路径，用 `in_shelf` 区分

浏览中的书（打开了详情或在读、没有加入书架）和书架上的书走同一套表，`in_shelf = false`。启动时删除所有 `in_shelf = false` 的书及其目录、正文。加入书架就是把 `in_shelf` 改为 true，并写入 `added_at`，目录、已加载的正文和进度自然都保留下来。

备选：浏览中的书只放在内存里，加入书架时再整体写入。这样阅读器要同时支持「内存里的书」和「数据库里的书」两种来源，加入书架时还要把内存里的目录、正文和进度搬进数据库，有两条路径。规格要的只是「重启后不保留」，用一个标志位加启动时清理就满足，阅读器只有一条路径。

### D4 书源级状态：启动时全量载入内存，写入同步生效、后台落盘

`PersistentSourceStore` 实现 rule_engine 的 `SourceStore`：

- 启动时（建 `RuleHost` 之前）读出 `source_kv` 全部未过期的行，放进内存表；已过期的行顺手删除。
- `get` 只读内存表，过期判断和 `MemorySourceStore` 一样。
- `put`、`delete` 先改内存表，再把这次写入追加到一个串行的落盘队列；队列按顺序执行 upsert/delete，失败时写一条书源日志（app-storage 的「书源级状态读写即时可见」）。
- `putMemory` 等只在内存里的接口直接委托给内存表，不落盘。

内存里的值就是唯一的真相，数据库只是它的镜像。备选是 `get` 时同步读数据库：drift 的接口是异步的，主 isolate 上又不能阻塞，做不到。

载入量：书源级状态是少量键值，书源偶尔会缓存整页内容，全部载入也在几 MB 以内。

### D5 Cookie 落盘：rule_engine 的 `CookieStore` 增加初始值和变更回调

```dart
CookieStore({Map<String, String> persistent = const {}, void Function(String domain, String? cookie)? onPersistentChanged});
RuleHost({..., CookieStore? cookieStore});
```

- 只有持久 Cookie 落盘；会话 Cookie 仍只在内存里（app-storage 的「持久 Cookie」）。
- `CookieStore` 里每一处改写持久 Cookie 的地方（`saveResponse` 的持久部分、`setCookie`、`replaceCookie`、`removeCookie`）在改完之后，用这个域名的新值调用一次回调（删除时为 null）。app 侧的回调把它追加到 D4 的同一个落盘队列。
- 匹配、合并、按注册域名分组的语义不变，`source-request` 的规格不需要改；只是给 rule_engine 补测试：初始值能被请求带上，每种改写触发一次回调且值正确。

备选：app 定时把 `CookieStore` 整体快照写盘。不需要改 rule_engine，但快照间隔内的写入会在崩溃时丢失，而且要拿到内部的 Map；变更回调更直接，也只多十几行。

### D6 引擎接入：一个池，最多 6 个 worker，批量任务限流，给交互留出 worker

- 全 app 一个 `WorkerPool`，大小 6。上限来自 Dart VM，而不是内存：同一个 isolate group 里同时运行的 isolate 最多 8 个（`MaxMutatorThreadCount`：16MB 新生代 / 512KB TLAB / 4，与核数无关），阻塞在宿主请求里的 worker 也占一个位置。超过之后，主 isolate 每处理一条消息都要等 120ms 的抢占超时才能从阻塞的 worker 手里抢到位置，越多越慢，最后卡死。所以 worker 数 = 8 − 主 isolate − drift 的后台 isolate = 6。
  - 实测（macOS 和 iOS 模拟器一致）：N 个 worker 在 JS 里反复做阻塞的宿主调用，6 个 1.6 秒，8 个 9 秒，12 个 19 秒，16 个卡死。只阻塞一次时 12 个也能完成，所以简单的压测发现不了。
  - 最初按「worker 内存便宜」定了 8，又按搜索计时改成 16，iOS 模拟器上搜到一半卡死（主线程停在 `IsolateGroup::IncreaseMutatorCount`）才发现这个上限。
- 搜索和书架更新是批量任务，通过 app 里的一个限流器提交：同时最多 4 个在池里。详情、目录、正文（包括预加载）直接提交。池的队列是先进先出的，这样至少有 2 个 worker 不会被批量任务占满。
- 搜索计时（随机 200 个书源去重后 192 个，搜索「斗罗大陆」）：macOS 144 秒，iOS 模拟器 151 秒。时间主要花在慢站点等到超时（连接 15 秒、单个任务 60 秒）上；要再快，方向是缩短搜索的超时，而不是加 worker。
- 每次搜索、每次书架更新各用一个 `CancelToken`；停止、换关键词、离开页面时取消它。限流器里还没提交的任务一起丢弃。
- 单个任务的截止时间用池的默认 60 秒（book-search 的「发起搜索」）。

备选：给 blocking_bridge 的池加优先级队列。语义更精确，但要改阻塞桥并补测试；限流器只在 app 里，够用。备选：交互和批量各一个池。两个池在同一个 isolate group 里，加起来仍受 6 个的上限，没有收益。备选：worker 用独立的 isolate group（`Isolate.spawnUri`）绕开上限：Flutter 的 AOT 构建不支持。

### D7 搜索：按「代」丢弃过期结果，合并键是去空白的书名加作者

- 搜索控制器每次发起搜索时代数加一，并新建 `CancelToken`。任务完成的回调先比较代数，不是当前代就丢弃：取消和任务完成之间有竞争，单靠取消挡不住已经在回调路上的结果（book-search 的「停止与取消」）。
- 合并：`Map<(name, author), MergedBook>`，`MergedBook` 按完成顺序记住各书源的 `SearchBook`，展示字段取第一个。每批结果到达后整体重排（三组、组内按书源数降序、再按首次出现顺序）。结果规模是几百条，整体重排的开销可以忽略，不维护增量顺序。
- 失败按书源记录：书源名、错误类型（`RuleEngineException` 的子类名对应成中文）、错误信息。

### D8 正文排版：纯函数，输出带偏移的段落

```
formatChapter(title, content) → (title, paragraphs: [(text, offset)])
```

- 按 reader 规格的「正文排版」切段、去空白、缩进、去重复标题、替换 `<img>`；`offset` 是这一段在排版后正文（各段以换行连接）里的起始字符偏移。
- 阅读进度存的就是这个偏移（D9）。排版规则是确定的，同样的正文得到同样的偏移；以后改排版规则（比如加净化规则）时，偏移的含义会变，但只影响旧进度的段内定位，章节不受影响。
- 纯函数，单元测试覆盖规格里的场景。

### D9 阅读页：一章一个滚动视图，用段落的布局位置换算进度

- 一章的段落放进 `SingleChildScrollView` 里的 `Column`，每段一个 `Text`。一章通常只有几十到几百段，全部布局没有压力。这样每段都有布局结果，保存时能找到第一个可见段落，恢复时能直接滚到某段。懒加载的列表做不到滚到还没构建的段落。
- 保存进度：取视口顶部所在的段落，存它的 `offset`。触发时机：切换章节、离开阅读页、`AppLifecycleState` 进入 inactive 或 paused、滚动停止 2 秒后（防止崩溃时丢太多）。
- 恢复：布局完成后（下一帧），找到 `offset` 所在的段落，把它滚到顶部。改字号、行距时也走同一个流程：改之前先取当前偏移，重排后滚回去。
- 上一章、下一章、目录跳转都从章首开始；章节切换时先保存旧章节的进度。
- 预加载：当前章显示后，提交下一个非卷章节的正文任务，结果写入缓存；同一章同时只有一个加载任务（阅读页和预加载共用一个「进行中」表）。
- 主题颜色（背景 / 文字）：亮 `#FFFFFF` / `#1F1F1F`，暗 `#121212` / `#B8B8B8`，护眼 `#F2E8CF` / `#3B3326`。字号、行距按 reader 规格的范围和默认值。

备选：`scrollable_positioned_list`。能按下标滚动，但它是 google.dev 下已停止维护的包，过不了稳定性门槛；而且分页排版会推翻滚动方案，没必要为滚动引入依赖。

### D10 书源导入

- 文件：`file_selector` 的 `openFile`（flutter.dev 官方包），macOS 沙盒加 `com.apple.security.files.user-selected.read-only`。
- 网址：在主 isolate 上用 `HttpClient` GET，30 秒超时，按 UTF-8 解码（书源 JSON 都是 UTF-8）。这不是书源请求，不走引擎、不带 Cookie。
- 解析用 `loadBookSources`，跳过的条目和原因直接来自它的结果。启用状态从原始 JSON 的 `enabled` 读取（`false` 才停用）。
- 写入时 `json` 列存原始对象重新编码后的文本。导出时解析回来，覆盖 `enabled` 字段后输出（source-management 的「导出书源」）。

### D11 书源日志

`RuleHost.onLog` 把日志放进主 isolate 上一个容量 500 的环形缓冲区，日志页订阅它。显示时用书源地址查当前的书源名，查不到（已删除）时显示地址。存储层的落盘错误也写进同一个缓冲区。

### D12 书架更新与当前章节定位

- 下拉刷新时，对书架上书源仍存在的书逐本提交目录任务（经 D6 的限流器）。成功后在一个事务里替换 `chapters`，更新 `books` 的章节数、最新章节名和 `source_data`（目录链路更新过的书籍）。
- 当前章节定位按 bookshelf 规格的「目录更新后定位当前章节」：用 `dur_chapter_url` 在新目录里找下标，找不到时保留原序号并截到范围内。章节地址是目录里最精确的章节标识（目录链路按地址去重），序号会随着插入、删除章节变化，章节名可能重复。
- 失败和「书源不存在」只保存在本次运行的内存里，作为书架项上的标记，不落盘。
- 下拉刷新在桌面上用鼠标不方便，AppBar 上另有一个「更新目录」按钮，执行同一个操作。

## Risks / Trade-offs

- [启动时全量载入书源级状态，书源大量使用 `cache.put` 时启动变慢] → 载入时记录行数和耗时；超过阈值再改成按书源懒加载。
- [后台落盘队列在 app 被杀时丢失最后几次写入] → 写入只在退出前的几百毫秒内有风险；进入后台时等待队列清空（`AppLifecycleState.paused` 里 await 队列）。
- [worker 上限 6 是按 Dart 3.8 的 VM 算的，SDK 升级后可能变] → 引用了 VM 源码里的公式；升级 Flutter 时用同样的反复阻塞压测再测一次。
- [6 个 worker 下全量搜索要两分多钟] → 以后缩短搜索的超时、或者按书源响应时间排序先搜快的；都不改结构。
- [一章全部布局，超长章节（几万字）首帧慢] → 冒烟时记录最长章节的布局时间；分页排版的 change 会重写这部分。
- [浏览中的书和书架上的书同表，崩溃后残留到下次启动] → 启动时清理；规格只要求重启后不保留。
- [Material 3 默认界面与以后的设计稿差距大] → 页面按功能拆分组件，样式集中在主题里，以后换设计主要改主题和少量组件。

## Migration Plan

新 app，没有已有数据。数据库 schema 版本从 1 开始，以后的变更走 drift 的迁移。rule_engine 的改动只增加可选参数，现有调用方（spike、tool、测试）不用改。

