## Why

用户 2026-11-11 要求：iOS 上的书源功能默认关闭，在关于页连点「懒猫阅读」版本 10 次才打开；打开后记在本地，以后覆盖安装新版本不用再点。

app 没有本地导入，书架、搜索、发现、详情都靠书源；关闭书源功能时，界面上应该看不到任何和书源有关的入口，app 看起来就是一个空书架。

## What Changes

- **iOS 书源功能开关**：iOS 上默认关闭，Android 和 macOS 一直打开。关闭时隐藏底部「发现」tab、书架顶栏的「搜索」、空书架的「去搜索」、设置里「书源」「替换净化规则」那一组。
- **关于页解锁**：书源功能关闭时，在关于页连点名称和版本那一行 10 次打开它，提示「已开启书源功能」，各入口立即出现，不用重启。点的过程中没有提示、没有点击反馈；离开关于页重新计数。
- **打开后落盘**：存进数据库的设置表，覆盖安装（升级）时数据库保留，不用再点；卸载重装后数据清空，需要重新点。
- 已经导入过书源的 v0.1.0 iOS 用户升级后同样是关闭的，需要点 10 次（用户 2026-11-11 决定，见设计 D5）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `app-shell`：新增「iOS 书源功能开关」；「底部 tab」在书源功能关闭时只有书架、设置两个 tab。
- `bookshelf`：「书架列表」的空书架提示在书源功能关闭时不提供「去搜索」。
- `settings`：「设置页入口」在书源功能关闭时没有「书源」「替换净化规则」；「关于页」可以连点版本打开书源功能。

## Impact

- `app/lib/settings/source_feature.dart`（新）：开关 `sourceFeatureProvider`，读写设置表里的 `sourceFeature.unlocked`。
- `app/lib/app_shell.dart`、`app/lib/bookshelf/bookshelf_page.dart`、`app/lib/settings/settings_page.dart`：按开关隐藏入口。
- `app/lib/settings/about_page.dart`：名称和版本那一行计数解锁。
- 测试：新增 `app/test/settings/source_feature_test.dart`；`integration_test/app_flow_test.dart`、`real_sources_test.dart` 启动前把开关写成已打开，iOS 上照常走设置 → 书源和搜索。
