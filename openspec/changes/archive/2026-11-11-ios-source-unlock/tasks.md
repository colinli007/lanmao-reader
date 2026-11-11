## 1. 开关和入口

- [x] 1.1 `app/lib/settings/source_feature.dart`：`SourceFeatureNotifier` 和 `sourceFeatureProvider`（D1），`unlock()` 写设置表的 `sourceFeature.unlocked`（D2）。验证：source_feature_test 覆盖 app-shell「iOS 上默认关闭」「重启后仍然打开」「其它平台一直打开」。
- [x] 1.2 `app_shell.dart`、`bookshelf_page.dart`、`settings_page.dart`：按开关隐藏发现 tab、搜索、去搜索、书源一组（D3）。验证：source_feature_test 依次切到设置和书架，检查每个入口在关闭时不存在、打开后存在。
- [x] 1.3 `about_page.dart`：`_VersionTile` 计数解锁，`GestureDetector` 没有点击反馈（D4）。验证：source_feature_test 覆盖 settings「连点版本打开书源功能」「离开关于页重新计数」。

## 2. 验证

- [x] 2.1 `integration_test/app_flow_test.dart`、`real_sources_test.dart` 启动前写入 `SourceFeatureNotifier.unlockedKey`，iOS 上照常走设置 → 书源和搜索。验证：app_flow_test 在 iOS 模拟器上通过。

  结果（2026-11-11，iPhone 17 模拟器 iOS 26.3）：app_flow_test 3 个通过。real_sources_test 要连真实书源网站，这次没有跑。
- [x] 2.2 `flutter analyze`、`flutter test`。验证：全部通过。

  结果（2026-11-11）：analyze 无问题，426 个测试通过（原有 420 个，新增 6 个）。
- [x] 2.3 iOS 模拟器上实际操作并截图：关闭时的书架和设置、连点 10 次后的关于页、打开后的设置。验证：截图和规格一致。

  结果（2026-11-11，iPhone 17 模拟器，内存数据库，不动模拟器上 app 的数据）：关闭时底部只有书架、设置，书架只显示「书架还是空的」，设置页没有书源一组；连点 10 次弹出「已开启书源功能」，返回设置页能看到书源、替换净化规则，底部出现发现。第一次截图发现点版本那一行有水波纹，改成 `GestureDetector` 后重新截图，没有水波纹。
- [x] 2.4 用户确认后在 `feat/ios-source-unlock` 上提交，同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-11）：代码和提案提交为 9fcfe6c；app-shell 新增「iOS 书源功能开关」、替换「底部 tab」，bookshelf 替换「书架列表」，settings 替换「设置页入口」「关于页」；`openspec validate --specs --strict` 22 项通过。
