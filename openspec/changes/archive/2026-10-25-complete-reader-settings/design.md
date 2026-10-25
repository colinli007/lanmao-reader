## Context

动机和范围见 proposal.md，行为要求见 `specs/reader/spec.md`：

- 修改「正文排版」「分页排版」「阅读设置」。
- 新增「屏幕常亮」「音量键翻页」。

### 现状

- **设置**：
  - `ReaderSettings` 有字号、行距、主题、翻页方式、跟随系统深色五项。
  - `fromMap` 读的时候夹到范围内，`toMap` 写回 `settings` 表，`ReaderSettingsNotifier.update` 立即生效并落盘。
- **排版参数**：
  - `LayoutSpec(fontSize, lineHeight, size)`。其中 `indent` 写死为两个字宽，`paragraphSpacing` 写死为 0.6 倍字号。相等比较只看这三个字段。
  - `ChapterWindow.resize(spec)` 在参数不同时重排三章，停在原来那个字上。字号和行距的「改了不丢位置」都靠这条路径。
- **边距**：
  - `PageGeometry.margin = 20` 是常量。
  - 分页模式：`bodyInsets` 用它算正文区域，`PagePainter` 按 `insets.left` 画页眉页脚。
  - 滚动模式：`ScrollReaderView` 直接拿常量做 `ListView` 的左右 padding。
- **点击翻页**：
  - 分页：`PagedView._tapTurn(forward)` 处理，包括正在播放的动画、章节之间连续翻页、到头的提示。
  - 滚动：`ScrollReaderView._onTapUp` 里算「一屏减一行」再 `animateTo`。
  - 两者都先看 `menu` 是否显示。
- **屏幕常亮**：`MainActivity` 只在可调试的构建里给窗口加了 `FLAG_KEEP_SCREEN_ON`，这是为了集成测试跑几分钟时不息屏。app 自己没有保持亮屏的功能。
- **原生代码**：
  - 目前没有自定义的 `MethodChannel`。
  - 依赖里有 `package_info_plus`、`file_selector`、`path_provider` 这类官方或社区插件，引入前都按 `docs/review/依赖稳定性审查-2026-09-26.md` 的标准评估过。

## Goals / Non-Goals

**Goals:**

- 新的三项排版设置走现有的「参数变了就重排、停在原来那个字」路径，不另写定位逻辑。
- 音量键翻页和点击翻页完全是同一条路径，动画、跨章、到头提示的行为一致。
- 屏幕常亮只在阅读页可见时生效，离开就恢复，不会让 app 在后台或者其它页面也一直亮屏。

**Non-Goals:**

- 键盘翻页（方向键、空格、PageDown）：等桌面端有需要时再加，按键入口会和这次的一样。
- 屏幕常亮的时长档位。

## Decisions

### D1 设置的模型和落盘

`ReaderSettings` 新增五个字段：

| 字段 | 设置表的键 | 类型 | 范围 / 默认 |
|---|---|---|---|
| `paragraphSpacing` | `reader.paragraphSpacing` | 字号的倍数 | 0 到 2，默认 0.6 |
| `indent` | `reader.indent` | 字数 | 0 到 4，默认 2 |
| `margin` | `reader.margin` | 逻辑像素 | 8 到 48，默认 20 |
| `keepScreenOn` | `reader.keepScreenOn` | 布尔 | 默认 false |
| `volumeKeyTurn` | `reader.volumeKeyTurn` | 布尔 | 默认 true |

- 读取时夹到范围内，和现有字段一致。
- 写入时段距按一位小数格式化，和行距一样，避免 `0.7000000000000001`。
- 段距用字号的倍数，缩进用字数，都是相对字号的量：调字号时它们跟着变，比例不变。现在写死的 `fontSize * 0.6`、`fontSize * 2` 就是这样，默认值保持现有效果。

### D2 排版参数：段距和缩进进 `LayoutSpec`，边距进正文区域

`LayoutSpec` 增加 `paragraphSpacingRatio` 和 `indentChars` 两个字段：

- `indent`、`paragraphSpacing` 两个 getter 改为按这两个字段计算。
- 相等比较和 `hashCode` 带上这两个字段。

这样调段距、缩进时，`resize` 自然判断为「参数变了」，走原来的重排和定位。

左右边距不进 `LayoutSpec`，它决定的是正文区域：

- `PageGeometry.bodyInsets(safeArea, margin)` 用设置的边距。
- 边距一变，`size` 就变，同样触发重排。
- 页眉页脚按 `insets.left` 和宽度画，自动跟着对齐。
- `ScrollReaderView` 的左右 padding 从 `LayoutSpec` 推不出来，改为由阅读页把边距传进去。
- `PageGeometry.margin` 常量删掉，默认值放在 `ReaderSettings` 里。

**否决的方案**：把边距也放进 `LayoutSpec`。排版只关心正文宽度，边距已经通过 `size` 体现了。放进去会让两个字段表达同一件事。

### D3 音量键：在 Dart 里处理，复用点击翻页的那条路径

Android 的 Flutter embedding 会把所有按键事件交给框架。框架处理了（`KeyEventResult.handled`）就不再交回系统；没处理的再交回 Activity，系统照常调音量。所以只要在 Flutter 里处理，就能做到「翻页时不调音量，其它时候照常调音量」，不需要原生代码。实现时第一项任务就是在模拟器上确认这一点，见 Risks。

处理的位置是 `PagedView` 和 `ScrollReaderView`：

- 各自包一层 `Focus(autofocus: true, onKeyEvent: ...)`。
- 翻页本来就在这两个视图里：`PagedView._tapTurn` 处理动画和跨章。滚动视图把「滚一屏」从 `_onTapUp` 里抽成 `_scrollScreen(forward)`，点击和音量键都调用它。
- 放在阅读页层面的话，要把这两个视图内部的翻页操作暴露出去，所以不放那里。

按键的判断：

- 按键是 `audioVolumeDown` 或 `audioVolumeUp`，「音量键翻页」打开，平台是 Android，菜单隐藏：
  - `KeyDownEvent`：翻页或者滚一屏，返回 handled。
  - `KeyRepeatEvent`、`KeyUpEvent`：只返回 handled，不翻页。这样按住不连续翻，系统也收不到这次按键。
- 其它情况返回 ignored，交回系统调音量。

焦点：

- 设置面板是模态路由，目录是 Scaffold 的抽屉，两者打开时焦点在它们自己的范围里，视图的 `Focus` 收不到按键，音量键照常调音量。这正是规格要的行为。
- 关闭后焦点回到视图。这一点要测：设置面板和抽屉关闭后再按音量键，能翻页。

### D4 屏幕常亮：自己写一个 channel，不引入 wakelock_plus

`reader/screen_awake.dart` 里有一个 `ScreenAwake`：

- 一个 `MethodChannel('novel_reader/screen')`，一个方法 `keepOn(bool)`。
- 记住上一次设的值，相同时不再调用。
- 由 `screenAwakeProvider` 提供，不做全局单例：每个 ProviderScope 一份「上一次设的值」，测试里换成记录调用的假实现，不用 mock channel。

原生实现：

- **Android**：`MainActivity` 处理 `keepOn`，给窗口加上或去掉 `FLAG_KEEP_SCREEN_ON`。可调试的构建一直保留这个标志，`keepOn(false)` 不清掉它，否则阅读页一退出，集成测试中途就会息屏。可调试的包括 debug 和 profile 构建，只有 release 构建按调用加上、去掉。
- **iOS**：`AppDelegate` 里设 `UIApplication.shared.isIdleTimerDisabled`。
- **macOS**：`MainFlutterWindow` 里用 `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, ...)` 创建断言，关闭时 `IOPMAssertionRelease`。

**为什么不用 `wakelock_plus`**：

- 它是一组联邦插件，带进来 `wakelock_plus_platform_interface`、`dbus`、`win32`，还有它自己锁定的 `package_info_plus` 版本区间。我们只用三个平台各一行的系统调用。
- 按依赖审查的标准，为这么小的功能引入一串依赖不划算，以后升级 Flutter 也多了一处可能卡住的地方。
- 自己写的代价是三段各十来行的原生代码，以及一个可以在 Dart 侧用假 channel 测的接口。

**什么时候常亮**：阅读页按「设置打开 并且 app 在前台」计算出想要的状态，再交给 `ScreenAwake`：

- 进入阅读页时（`initState`）计算一次；设置变化时用 `ref.listen` 重新计算，回调不在构建期间执行。
- 现有的 `AppLifecycleListener` 加上 `onShow`、`onHide`。
- `dispose` 时设为 false。

Android 窗口不可见时 `FLAG_KEEP_SCREEN_ON` 本来就不起作用，iOS 的 idle timer 只影响前台 app。但 macOS 的断言是全局的：阅读页开着时把 app 切到后台，不释放的话显示器就一直不熄。所以统一按前后台处理，三个平台的逻辑一样。

### D5 设置面板

- `showModalBottomSheet(isScrollControlled: true)`，内容放进 `SingleChildScrollView`，项多了在小屏上也能滚动。
- 新的数值项照现有的写法，用左边标签加 `Slider`：
  - 段距按 0.1 取整，缩进按 1 取整，边距按 4 取整。
- 两个开关用 `SwitchListTile`。「音量键翻页」只在 `defaultTargetPlatform == TargetPlatform.android` 时显示。

## Risks / Trade-offs

- **[Android embedding 收不到或交不回音量键]** 如果 Flutter 收不到音量键，或者处理后系统仍然调了音量，D3 不成立。
  - 缓解：tasks 第一项先在模拟器上验证，用 `adb shell input keyevent KEYCODE_VOLUME_DOWN` 发键，看是否翻页，再看 `adb shell dumpsys audio` 里媒体音量有没有变。
  - 不成立时改为：`MainActivity` 重写 `dispatchKeyEvent`，Dart 通过同一个 channel 告诉原生「现在接管音量键」，原生把按下事件转给 Dart。只影响 D3 的实现，规格不变。
- **[焦点没回到视图]** 关掉设置面板或目录后，如果焦点没回来，音量键就不翻页了。
  - 缓解：widget 测试覆盖「关掉面板后按音量键能翻页」。如果不能，在面板和抽屉关闭时对视图的 `FocusNode` 调用 `requestFocus`。
- **[边距、段距调大后可能一页放不下一行]** 只有极端组合才会这样：边距 48、字号 40、行距 3，放在很矮的窗口里。现有切页逻辑在空页上第一行放不下时会强制放下（add-paged-reader 设计 D5），不会死循环，所以只是显示上挤，可以接受。
- **[可调试构建里屏幕常亮看不出效果]** Android 的 debug 和 profile 构建都可调试，一直常亮（Flutter 的 profile 构建类型在 debug 的基础上建），「关闭时按系统熄屏」只能在 release 构建上验证。
  - 缓解：手动验证用 release 构建，看 `adb shell dumpsys window` 里窗口标志有没有 `KEEP_SCREEN_ON`。
