## Context

「屏幕常亮」已经有一套现成的结构（complete-reader-settings 设计 D4）：

- `ScreenAwake` 经平台通道 `novel_reader/screen` 的 `keepOn(bool)` 交给原生，记住上一次的值，相同的不再调用；测试里换成记录调用的实现。
- `ReaderPage` 在 `initState`、`AppLifecycleListener` 的 `onHide` / `onShow`、设置变化时调用 `_updateScreen()`，`dispose` 时关掉。

Legado 的亮度（`ReadMenu.setScreenBrightness`）：

- 改的是 Activity 窗口的 `WindowManager.LayoutParams.screenBrightness`。跟随系统时设成 `BRIGHTNESS_OVERRIDE_NONE`。
- 数值 0 到 255，默认 100；小于 1 时用 0.004，避免屏幕全黑。
- 窗口属性只属于阅读页的 Activity，离开阅读页自然恢复。

## Goals / Non-Goals

**Goals：** 阅读页显示期间用自己的亮度，离开或退到后台就恢复；调的时候立即看到效果；Android 不碰系统设置。

**Non-Goals：** 夜间单独一份亮度、屏幕边上的竖亮度条、macOS。

## Decisions

### D1 「阅读页的亮度」由什么决定：阅读页正在显示、app 在前台、没有跟随系统

亮度是阅读页这块屏幕的属性，生效的条件和屏幕常亮完全一样：阅读页在显示、app 在前台。所以不另起一套生命周期，而是在 `_updateScreen()` 里同时算出常亮和亮度两项，交给各自的对象。条件不满足或者跟随系统时，亮度是「不覆盖」（`null`）。

`ScreenBrightness` 和 `ScreenAwake` 并列：同一个通道，方法 `brightness`，参数是 0.01 到 1 的数或 `null`；记住上一次的值，相同的不再调用。测试里同样换成记录调用的实现。

### D2 各平台怎么实现

- **Android**：`window.attributes.screenBrightness = value ?: BRIGHTNESS_OVERRIDE_NONE`。我们只有一个 Activity，所以离开阅读页时必须由 Dart 主动设回 `null`，不能像 Legado 那样靠 Activity 结束。
- **iOS**：`UIScreen.main.brightness` 是整块屏幕的，没有只属于一个窗口的亮度。第一次设值时记下原来的亮度，设 `null` 时设回去并清掉记录。退到后台时 Dart 会设 `null`，所以不会把改过的亮度留给别的 app。
- **macOS**：没有公开接口。`ScreenBrightness.supported` 只在 Android 和 iOS 上为真，不支持时外观面板不显示亮度这一行，阅读页也不调用。

### D3 数值范围和默认值

滑块 0.01 到 1.0，显示为百分比。下限不是 0：Android 上 0 在部分机型上会让屏幕几乎全黑，Legado 也把 0 换成 0.004。默认 0.4，约等于 Legado 默认的 100/255。

「跟随系统」默认打开，升级后的用户第一次打开阅读页不会被改亮度。

### D4 外观面板的样子

主题色块上面加一行：太阳图标、滑块（占满中间）、「跟随系统」开关（`ChoiceChip`，选中用强调色，和书源列表的分组筛选一样）。跟随系统时滑块不可拖动，和 Legado 一样。

拖动时 `onChanged` 每次都调用 `readerSettingsProvider.update`：立即生效并落盘。写的是 settings 表里的几行，量很小，不另加「只预览不落盘」的状态。

## Risks / Trade-offs

- iOS 上用户在阅读页里从控制中心调了亮度，离开阅读页时会被设回进阅读页之前的亮度。iOS 上的阅读 app 普遍这样，接受。
- iOS 只能在真机上看效果，模拟器的 `UIScreen.brightness` 不改变显示。按用户的安排，iPhone 上的检查放到最后的真机测试里。
