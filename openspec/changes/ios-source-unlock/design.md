## Context

- 底部 tab 在 `AppShell`：书架、发现常驻（`Offstage`），设置只在选中时构建（redesign-minimal-ui 设计 D1）。
- 书源相关的入口：发现 tab、书架顶栏的「搜索」和空书架的「去搜索」、设置页的「书源」「替换净化规则」。详情、目录、阅读菜单和书架选项单里的「换书源」只能从书架上的书或搜索、发现进入，没有书源时到不了。
- 设置存在数据库的 `settings` 表（键值都是文本），启动时 `startServices` 读出整张表，经 `initialSettingsProvider` 交给各个 Notifier；`ReaderSettingsNotifier` 改动时 `putSetting` 落盘。
- 数据库在应用支持目录，iOS、Android 覆盖安装时保留，卸载时清空。

## Goals / Non-Goals

**Goals：** iOS 上默认看不到书源相关的入口；连点关于页的版本打开，打开一次以后升级也保持打开。

**Non-Goals：**
- 不提供关闭的操作：打开以后一直是打开的，要关闭只能卸载重装。
- 不限制书源的使用：打开前已经在书架上的书照常阅读、更新目录、换书源（只有升级上来的老用户会遇到，见 D5）。
- Android、macOS 不变。

## Decisions

### D1 一个开关，各入口只看它

`sourceFeatureProvider`（`NotifierProvider<…, bool>`）是唯一的状态：`build()` 返回「不是 iOS，或者设置表里 `sourceFeature.unlocked` 是 `true`」。发现 tab、书架的搜索、设置页的书源一组都 `watch` 它，打开时这些地方同时重建，不用重启。

平台用 `defaultTargetPlatform` 判断，和书架上 macOS 才显示的「更新目录」按钮相同，测试里可以用 `TargetPlatformVariant` 切换。

为什么不在每个入口各自判断平台：「关闭」是一个状态，散在各处会出现漏改的入口；集中成一个开关，新增在线入口时只要 `watch` 它。

### D2 打开后存进设置表

`unlock()` 先改状态，再 `putSetting('sourceFeature.unlocked', 'true')`，和 `ReaderSettingsNotifier.update` 一样不等落盘。下次启动从 `initialSettingsProvider` 读回来。覆盖安装时数据库保留，所以升级后不用再点。

为什么不用 `shared_preferences` 之类的单独存储：设置已经有一张表和一套启动时读取的流程，再加一种存储没有好处。

### D3 关闭时隐藏全部在线入口

隐藏发现 tab、书架顶栏的搜索、空书架的「去搜索」、设置里「书源」「替换净化规则」一组。空书架只剩「书架还是空的」。

为什么连替换净化规则一起隐藏：替换规则只作用于书源取到的正文，没有书源时这一项没有意义；它和书源在同一组卡片里，整组去掉，设置页不会留下只有一项的卡片。

### D4 计数在关于页里，没有提示和点击反馈

名称和版本那一行是 `_VersionTile`（`ConsumerStatefulWidget`），自己记点击次数，满 10 次调 `unlock()` 并提示「已开启书源功能」。计数是这个页面的状态，离开关于页就清零。

用 `GestureDetector` 包住 `ListTile`，而不是 `ListTile.onTap`：后者点击时有水波纹，等于告诉别人这一行能点。中途也不提示「再点 N 次」。打开以后 `onTap` 为 null，再点没有反应。

### D5 已导入书源的老用户不特殊处理

v0.1.0 的 iOS 用户升级后同样是关闭的：书架上的书照常阅读，但搜索、发现、书源管理要点 10 次才出现。

不按「已经有书源就当作打开」处理：那是拿「有没有书源」去猜「有没有解锁过」，两者不是一回事，而且这个判断会一直留在代码里。v0.1.0 当天发布，iOS 上几乎没有老用户（用户 2026-11-11 决定）。

## Risks / Trade-offs

- 卸载重装后要重新点：数据库随卸载清空，这是预期行为。
- 免费 Apple ID 自签的 app 7 天后要重新签名：重新签名、覆盖安装时数据保留，不用重新点；如果用户先卸载再装，就要重新点。
