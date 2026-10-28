## 1. 删代码

- [x] 1.1 删除 `app/lib/reader/volume_keys.dart`；`reader_settings.dart` 删掉 `volumeKeyTurn` 字段、`_volumeKeyTurn` 键，以及构造函数、`fromMap`、`toMap`、`copyWith` 里的相关处理。验证：`test/reader/reader_settings_test.dart` 去掉 `volumeKeyTurn` 以后通过；默认值用例的标题和断言只剩段距、缩进、边距、屏幕常亮四项。
- [x] 1.2 `paged/paged_view.dart`、`scroll/scroll_view.dart` 退回加音量键之前的样子：删掉 `volumeKeyTurn` 参数、它的注释和 `volume_keys.dart` 的 import，去掉外层的 `Focus`；滚动视图的 `_scrollScreen` 并回 `_onTapUp`，恢复原来那句「翻一屏减一行，留一行作为上下文」的注释。验证：和加音量键之前的版本比，`git diff 5f60b6d~1 -- app/lib/reader/paged/paged_view.dart app/lib/reader/scroll/scroll_view.dart` 里只剩左右边距（`margin`）相关的改动。
- [x] 1.3 `reader_page.dart`：不再给两个视图传 `volumeKeyTurn`；设置面板删掉只在 Android 上显示的「音量键翻页」开关和它上面那行注释。如果删完以后 `defaultTargetPlatform` 或某个 import 不再使用，也一起删掉。验证：`flutter analyze` 没有问题。

## 2. 测试

- [x] 2.1 `test/reader/reader_page_test.dart`：
  - 删掉「音量键翻页」整组用例
  - 删掉「「音量键翻页」只在 Android 上显示」
  - 设置面板落盘的用例去掉「音量键翻页」开关和 `volumeKeyTurn` 键，标题跟着改
  
  `test/reader/paged/paged_view_test.dart` 去掉 `volumeKeyTurn: false`。验证：带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test` 全部通过，用例总数比原来少的数目和删掉的用例数一致。

  结果（2026-10-28）：251 个全部通过，原来 260 个。少了 9 个：「音量键翻页」一组 7 个，每个只在一个平台上跑；「只在 Android 上显示」在 Android 和 iOS 上各跑一次，算 2 个。设置面板落盘的用例原来限定在 Android 上跑，只是为了让开关显示出来，现在去掉了这个限定。`foundation.dart` 是加音量键时为了 `defaultTargetPlatform` 引入的，`reader_page.dart` 和 `reader_page_test.dart` 里的这个 import 也一起删了。
- [x] 2.2 检查有没有删漏：在 `app/lib`、`app/test`、`app/integration_test` 里搜 `volumeKeyTurn|handleVolumeKey|volume_keys|audioVolume|音量键`。验证：没有结果。
- [x] 2.3 端到端：`integration_test/app_flow_test.dart` 在 Android 真机（或 emulator-5554）和 macOS 上跑（macOS 遇到 Caps Lock 断言时先切到 ABC 输入法，跑完切回）。另外在 Android 真机上装 debug 包，打开一本书，菜单隐藏时按音量减。验证：两个平台都通过；按音量键只弹出系统音量条，页面不翻。

  结果（2026-10-28）：app_flow 在 Redmi Note 14 Pro（debug）和 macOS（切到 ABC 输入法跑，跑完切回搜狗拼音并恢复 Caps Lock）上都通过。手工检查没有用 debug 包，改用现在的代码打的 release 包（release 密钥签名，`adb install -r`）。用户在手机上验证：按音量键不翻页，阅读设置里也没有这个开关了。

## 3. 文档

- [x] 3.1 PRD（`docs/产品需求-第一版-2026-10-18.md`）：
  - 4.5 节「音量键翻页（Android）」一行改为「已删除」，写明 2026-10-28 由用户决定、原因和 change 名。
  - 第七节第 7 步、第八节第 4 条里提到音量键翻页的地方，改成说明后来删掉了。
  
  验证：通读一遍，没有把音量键翻页说成第一版的功能。
- [x] 3.2 README 目录表里 `app/` 的说明去掉「Android 音量键翻页」；`docs/发布说明/v0.1.0.md` 去掉「Android 上可以用音量键翻页」。验证：在 `README.md`、`docs/发布说明/` 里搜「音量键」，没有结果。
- [x] 3.3 prepare-release 的 `tasks.md` 第 6.6 项：在音量键那一条下面注明「已由 remove-volume-key-turn 删除，不用检查」。验证：6.6 剩下的检查只有屏幕常亮（已完成）和覆盖升级。
