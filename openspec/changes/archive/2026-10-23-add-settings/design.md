## Context

动机和范围见 proposal.md，行为要求见 specs/settings/spec.md 和 specs/app-storage/spec.md。

### 现状

- **正文缓存**：
  - 存在 SQLite 的 `contents` 表里，主键是 (bookUrl, chapterUrl)，`reader_page.dart` 读写。
  - 只有两处会删：`removeBook`（移出书架）、`purgeBrowsingBooks`（启动时清理浏览中的书）。删行之后数据库文件不会变小。
- **数据库**：
  - `AppDatabase.open()` 用 `drift_flutter`，在后台 isolate 上执行查询。
  - 依赖锁定的 sqlite3_flutter_libs 是 0.5.42，带的 SQLite 版本高于 3.43，有 `octet_length()`。
- **阅读页的内存**：阅读页打开时，在内存里持有前后三章的排版结果。设置页从书架进入，那时阅读页已经关了，不存在内存里的正文要同步失效。
- **界面**：Material 3 默认组件，还没有按设计稿出界面。书架顶栏现在有三个按钮：更新目录、搜索、书源。
- **版本号**：只写在 `pubspec.yaml` 的 `version: 0.1.0`。构建时 Flutter 把它写进各平台的安装包（Android 的 versionName、iOS 和 macOS 的 CFBundleShortVersionString），Dart 代码里读不到。
- **模块边界**：`lib/online/` 以外不能引用 `rule_engine`，由 `module_boundary_test.dart` 检查。

## Goals / Non-Goals

**Goals:**
- 显示的缓存大小就是「清除能腾出的空间」，清除后磁盘空间真的回收。
- 版本号只有一个来源：`pubspec.yaml`。
- 设置页和关于页不依赖书源模块，以后做不带书源的版本时可以直接沿用。

**Non-Goals:**
- 阅读设置搬进设置页、应用级主题设置。
- 统计或清除书源级状态、Cookie、图片缓存（现在封面只有 Flutter 的内存图片缓存，不落盘）。
- 设置页、关于页按设计稿出界面：先用 Material 3 默认组件，以后随设计稿统一换。

## Decisions

### D1 缓存大小统计什么

用户看缓存大小，是为了判断清除能腾出多少空间。所以统计的信号是「清除时会删掉的那些行」的正文字节数：

```sql
SELECT COUNT(*), COALESCE(SUM(octet_length(content)), 0) FROM contents
```

章节数和字节数在一次查询里出来。

- **不用数据库文件的大小**：文件里还有书源、目录、书源级状态，以及删除后留下的空闲页，这些都不会因为清除而变化。拿文件大小当缓存大小，清除后数字对不上。
- **不用 `length(content)`**：它返回的是字符数，中文一个字占 3 个字节，会少算三分之二。
- **用 `octet_length` 而不是 `length(CAST(content AS BLOB))`**：后者会把每一行的正文都读出来再转换。前者在 UTF-8 数据库里能直接给出字节数，不需要转换。

标题只有几十个字节，不计入。

### D2 清除的实现：删除之后 VACUUM

`AppDatabase.clearContents()` 先执行 `DELETE FROM contents`，再执行 `VACUUM`。

- **为什么要 VACUUM**：SQLite 删除行之后，空出来的页只留在文件里给以后复用，文件不会变小。不 VACUUM，用户点了清除，系统存储里 app 的占用却没变，这和清除这个操作的本意相反。
- **为什么不用 `auto_vacuum = INCREMENTAL`**：已有的数据库要先完整 VACUUM 一次才能切换模式，还要做迁移。而清除是低频的手动操作，一次全量 VACUUM 就够了。
- **两步不放在一个事务里**：VACUUM 不能在事务里执行。如果 VACUUM 失败（比如磁盘空间不足，VACUUM 需要临时空间），删除已经生效，只是文件没有变小。这种情况下界面照常显示 0 章，失败写进日志。数据是正确的，只少回收了空间，不值得为它回滚删除。

统计和清除都放在 `database.dart` 里，和 `removeBook` 等方法并列。

### D3 设置页的状态

统计和「清除中」分开放：

- **统计**：`contentCacheStatsProvider` 是 `FutureProvider.autoDispose`，执行 D1 的统计。设置页 watch 它，没有值时显示「统计中」。离开设置页就丢掉，下次进入重新统计。不需要监听阅读页写缓存，因为两个页面不会同时打开。
- **清除中**：是「正文缓存」这一项自己的界面状态，放在它的 State 里。确认后先置为清除中，按钮不可用，所以不会重复发起；`clearContents()` 结束后 invalidate 统计，等新的统计出来再收起清除中，中间不闪「统计中」。
- **不用 AsyncNotifier 把清除也放进 provider**：清除中只有这一项关心。放进 provider 的话，要么另加一个状态类，要么靠「加载中但有旧值」去猜是在清除，都比一个局部变量绕。

确认对话框直接写在设置页组件里，不通过回调传递。

### D4 版本号用 package_info_plus

关于页通过 `PackageInfo.fromPlatform()` 读取安装包的 version。

- **不在 Dart 里写死版本常量**：那样就有两个版本号，改了 pubspec 忘了改常量，关于页就会显示错的版本，而用户正是拿这个版本号去和 Releases 对比的。
- **不用 `--dart-define` 传版本**：每个构建命令都要记得带上参数，漏了不会报错。
- **为什么选 package_info_plus**：它是 Flutter Community 的 plus 系列插件，读的正是 Flutter 写进安装包的那个值，Android、iOS、macOS 都支持。新增依赖只此一个。

测试里用 `PackageInfo.setMockInitialValues` 注入版本号。

### D5 关于页的内容

- **app 名称**：「小说阅读」，和 `MaterialApp.title` 用同一个常量。
- **开源协议**：显示文字「GPL-3.0」。
- **源代码地址**：显示 `https://github.com/colinli007/novel-reader`，点击后复制到剪贴板，并弹出 SnackBar 提示。
  - **不引入 url_launcher 直接打开浏览器**：多一个插件，换来的只是少一步粘贴，不划算。
  - **为什么要显示这个地址**：app 不上架应用市场，Releases 页面是用户获取新版本的唯一渠道。
- **免责声明**：文字按 spec 写。它属于社区版的说法，以后做不带书源的版本时改这一处文案就行，现在不为此做抽象。
- **开源许可**：调用 Flutter 自带的 `showLicensePage`，列出所有依赖包里的 LICENSE 文件，包括 path 依赖。quickjs_ng_ffi 和 native_synchronization 的 LICENSE 会一起出现。applicationName 和 applicationVersion 用同一份信息。

### D6 入口和页面结构

- **入口**：书架顶栏的 actions 末尾加一个设置按钮（`Icons.settings_outlined`，tooltip「设置」）。加上之后顶栏一共四个图标按钮，在 360dp 宽的手机上放得下。
- **页面**：设置页和关于页都用 `ListView` 加 `ListTile`。
  - 「正文缓存」项：标题「正文缓存」，副标题是「N 章 · X.X MB」，尾部是一个「清除」按钮。
  - 「关于」项：点击 push 关于页。
- **大小格式化**：写成 `lib/settings/` 里的一个纯函数，单元测试覆盖。
  - 1024 进位，不足 1KB 显示整数字节，其余保留一位小数。

### D7 仓库文档

- 根目录加 GPL-3.0 的 `LICENSE`，用 GNU 官方全文。
- README 开头加免责声明，文字和关于页一致；目录说明里补上设置页。
- PRD 4.7 节「设置页」「关于页与免责声明」的状态改为已完成。

## Risks / Trade-offs

- **VACUUM 期间数据库被独占** → 清除是用户在设置页主动发起的，那时阅读页没有打开。可能同时在写的只有书架刷新写目录、书源级状态的后台落盘，drift 会把它们排在 VACUUM 之后执行。缓存几百 MB 时 VACUUM 可能要几秒，期间界面显示清除中，查询在后台 isolate 执行，不卡界面。
- **VACUUM 需要和数据库大小相当的临时空间** → 正好是磁盘快满、用户想清缓存的时候，最可能失败。按 D2 的处理，删除照样生效，失败只写日志。只有反复出现时才需要考虑 incremental vacuum。
- **测试环境的 SQLite 版本** → 宿主机单元测试用的是 `NativeDatabase.memory()` 加载的 SQLite。如果它低于 3.43，就没有 `octet_length`，测试会直接报错，不会悄悄算错。tasks 的第一步先确认它的版本。
- **package_info_plus 是平台插件** → Android、iOS、macOS 三端都要实际跑一次关于页，确认版本号显示正确。真机测试按约定放到最后。

## Open Questions

- 仓库现在是否公开：关于页显示的源代码地址按 `origin` 写。如果发布前改了仓库名或组织，只需要改这一个常量。
