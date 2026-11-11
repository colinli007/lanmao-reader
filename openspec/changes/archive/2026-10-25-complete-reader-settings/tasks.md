## 1. 先验证音量键（D3、Risks 第 1 条）

- [x] 1.1 在 Android 模拟器上验证 Flutter 能收到音量键，处理后系统不调音量：
  - 临时在阅读页挂一个 `Focus(onKeyEvent:)`，对 `audioVolumeDown` 返回 handled 并打日志。
  - 用 `adb shell input keyevent KEYCODE_VOLUME_DOWN` 发键，对比前后 `adb shell dumpsys audio` 里的媒体音量。
  - 再试返回 ignored，确认音量会变。
  - 验证完删掉临时代码，结论记在这一项下面。

  验证：两种返回值的结果都和 D3 的假设一致。不一致时停下来，按 Risks 里的办法改 design，和用户确认后再继续。

  结论（2026-10-25，emulator-5554，Android 16 / API 36，debug 构建）：D3 成立。
  - Flutter 返回 handled：原生 `dispatchKeyEvent` 只收到一次按下和一次抬起，不再交回系统；连按 3 次音量减，`dumpsys audio` 里媒体音量一直是 13。
  - Flutter 返回 ignored：原生层把同一个事件再交给系统一次，音量从 13 变成 14。没有声音在播放时，第一次按只弹出音量面板，不改音量，这是系统行为。
  - 系统音量面板显示期间，音量键交给面板，app 收不到。第一次探测就是因为先用 `media_session` 调了音量、弹出了面板，所以没收到。影响：刚调完音量、面板还没消失时，再按音量键仍是调音量。这是 Android 的正常行为，不处理。

## 2. 设置和排版参数

- [x] 2.1 `ReaderSettings` 新增 `paragraphSpacing`、`indent`、`margin`、`keepScreenOn`、`volumeKeyTurn`，键、范围、默认值按 D1；`copyWith`、`fromMap`、`toMap` 跟着改。验证：`test/reader/reader_settings_test.dart` 新增用例：
  - 缺省值和现在的排版效果一致：0.6、2、20
  - 超出范围的值被夹回
  - 段距写入时是一位小数
  - 布尔值的读写
- [x] 2.2 `LayoutSpec` 增加 `paragraphSpacingRatio`、`indentChars`，`indent`、`paragraphSpacing` 按它们计算，相等比较带上它们（D2）。验证：`test/reader/layout/chapter_layout_test.dart` 新增用例：
  - 缩进为 0 时首行从左边缘开始
  - 段距 1.2 时段间距是字号的 1.2 倍
  - 只改段距的两个 `LayoutSpec` 不相等
- [x] 2.3 `PageGeometry.bodyInsets(safeArea, margin)`，删掉 `margin` 常量；`ScrollReaderView` 的左右 padding 用阅读页传进来的边距（D2）。验证：
  - `test/reader/layout/page_painter_test.dart` 新增用例：边距 40 时页眉、正文、页脚的左边缘都在 40 处
  - `test/reader/reader_page_test.dart` 新增用例：滚动模式下边距 40 时段落离左边 40

## 3. 阅读页

- [x] 3.1 阅读页用新设置构造 `LayoutSpec` 和正文区域。验证：`reader_page_test.dart` 覆盖 reader「阅读设置」的这些场景：
  - 调大段距不丢位置
  - 调大左右边距
  - 正文排版「不缩进」：阅读页把缩进 0 交给排版参数；首字贴左边缘由 2.2 的排版测试覆盖
- [x] 3.2 设置面板改成可以滚动，加段距、首行缩进、左右边距三个滑块，以及屏幕常亮开关；「音量键翻页」开关只在 Android 上显示（D5）。验证：`reader_page_test.dart` 新增用例：
  - 拖动三个滑块和点两个开关后落盘
  - `TargetPlatform.android` 和 `TargetPlatform.iOS` 下「音量键翻页」一个显示、一个不显示
- [x] 3.3 屏幕常亮（D4）：
  - 新建 `reader/screen_awake.dart`：`ScreenAwake`，channel `novel_reader/screen` 的 `keepOn(bool)`，相同的值不重复调用。
  - 阅读页按「设置打开并且在前台」计算是否常亮，生命周期加上 `onShow`、`onHide`，`dispose` 时关闭。

  验证：`reader_page_test.dart` 用 `FakeScreenAwake`（覆盖 `screenAwakeProvider`）记录调用：
  - 设置打开时进入阅读页：调用 `keepOn(true)`；返回：调用 `keepOn(false)`
  - 设置关闭时：不调用 `keepOn(true)`
  - 阅读页里关掉设置：调用 `keepOn(false)`
  - 模拟 app 进入后台再回来：先 false 再 true
- [x] 3.4 三个平台的原生实现（D4）：
  - Android 的 `MainActivity`：可调试构建不清掉标志
  - iOS 的 `AppDelegate`
  - macOS 的 `MainFlutterWindow`

  验证：
  - Android 模拟器的 release 构建（profile 构建也可调试，会一直常亮）：`adb shell dumpsys window windows` 里，阅读页打开时有 `KEEP_SCREEN_ON`，返回书架后没有
  - macOS：`pmset -g assertions` 里，阅读页打开时有本 app 的 `PreventUserIdleDisplaySleep`，返回后没有
  - iOS 模拟器：调用不报错，结果记在这一项下面。模拟器不会自动锁屏，看不出效果，真机测试时再确认

  结论（2026-10-25）：
  - Android：profile 构建也是可调试的（Flutter 的 profile 在 debug 的基础上建），这时按设计保留标志，所以改用 release 构建验证。用临时探针跑 `flutter run --release`：阅读页打开时窗口标志有 `KEEP_SCREEN_ON`，返回后没有。
  - macOS：阅读页打开时 `pmset -g assertions` 里有本 app 的 `PreventUserIdleDisplaySleep`，返回后没有。断言名改成英文 `novel_reader reading`，中文名在 `pmset` 里显示为空。
  - iOS 模拟器（iPhone 17 Pro）：打开、返回各调用一次，没有异常；常亮效果等真机测试时确认。
  - iPhone 13 真机（2026-11-11，iOS 16.7.2，release 构建）：用户确认阅读页打开常亮时屏幕一直亮，返回书架后按时锁屏。
- [x] 3.5 音量键翻页（D3）：
  - `PagedView`、`ScrollReaderView` 包 `Focus(autofocus: true, onKeyEvent:)`
  - 滚动视图抽出 `_scrollScreen(forward)`，点击和按键共用
  - 按 D3 的条件判断：KeyDown 翻页，Repeat 和 Up 只消费

  验证：`reader_page_test.dart`，在 `TargetPlatform.android` 下用 `simulateKeyDownEvent` 等模拟按键，覆盖 reader「音量键翻页」的场景：
  - 音量减翻页
  - 按住不放：一次按下加多次重复，只翻一页
  - 滚动模式
  - 菜单显示时不翻、按键没有被消费
  - 关闭后不翻
  - 另加两个用例：打开设置面板再关掉，按音量键能翻页；打开目录再关掉，同样能翻页

## 4. 端到端和全量检查

- [x] 4.1 Android 模拟器上手动走一遍音量键：用 `adb shell input keyevent` 发键，覆盖翻页、菜单打开时调音量、关闭设置后调音量，结果记在这一项下面。验证：三种情况和规格一致。

  结果（2026-10-25，emulator-5554，debug 构建，临时探针每秒打印阅读位置，验证完已删除）：
  - 菜单隐藏：按一次音量减，阅读位置从 0 变成 260（翻了一页），媒体音量保持 14
  - 菜单显示：按两次音量减，位置不变，音量从 14 变成 13（第一次按只弹出音量面板）
  - 关闭「音量键翻页」后：按两次音量减，位置不变，音量从 13 变成 12
- [x] 4.2 全量测试：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，再跑 `flutter analyze`；`integration_test/app_flow_test.dart` 在 `-d macos` 和 `-d emulator-5554` 上跑。验证：全部通过，没有新的警告。

## 5. 文档

- [x] 5.1 PRD 4.5 节「段距、页边距、首行缩进可调」「屏幕常亮」「音量键翻页」改为已完成，第七节第 7 步标为已完成。验证：通读一遍，和实现一致。
- [x] 5.2 README 目录表里 `app/` 的说明补上新的阅读设置。验证：通读一遍，和实现一致。
