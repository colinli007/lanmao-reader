## Why

晚上在暗处看书时，系统亮度往往还偏亮，用户要退出去调系统亮度，回到其它 app 又得调回来。PRD 4.5 节把「阅读页亮度」列为 P1，还没有开始做。用户 2026-11-04 决定先在模拟器上把功能做完，这是其中的第二项。

## What Changes

做法参考 legado-E 的 `ReadMenu.kt`（`setScreenBrightness`、`upBrightnessState`）：

- 阅读菜单的外观面板，主题上面加一行亮度：太阳图标、亮度滑块、「跟随系统」开关。
- 「跟随系统」默认打开，这时滑块不可拖动，阅读页不改亮度。关掉后，阅读页显示期间屏幕亮度是滑块的值（1% 到 100%，默认 40%），拖动时立即生效。
- 离开阅读页、app 退到后台时恢复系统的亮度；回到前台、阅读页还在时重新使用阅读页的亮度。和「屏幕常亮」的时机相同。
- 亮度设置对所有书生效，落盘。
- 平台：
  - Android：只改阅读页所在窗口的亮度（`screenBrightness`），和 Legado 相同，不改系统设置。
  - iOS：只能改整块屏幕的亮度（`UIScreen.brightness`），所以改之前记下原来的亮度，恢复时设回去。
  - macOS：没有公开的接口能改屏幕亮度，不显示这一行。
- **不做**：
  - Legado 夜间主题单独存一份亮度。
  - Legado 在屏幕左侧或右侧显示竖着的亮度条、可以换边。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `reader`：新增「阅读页亮度」；「阅读菜单」的外观面板加上亮度；「阅读设置」加上亮度两项。

## Impact

- **app/lib/reader/**：
  - `reader_settings.dart`：加 `brightness`、`brightnessFollowSystem`，读写设置。
  - 新增 `screen_brightness.dart`：和 `ScreenAwake` 一样，经平台通道 `novel_reader/screen` 设亮度，记住上一次的值。
  - `reader_page.dart`：和屏幕常亮一起，在显示、前台、设置变化时设亮度，离开时恢复。
  - `menu/appearance_panel.dart`：亮度这一行，只在 Android 和 iOS 上显示。
- **原生**：Android `MainActivity.kt`、iOS `AppDelegate.swift` 的 `novel_reader/screen` 加 `brightness` 方法。macOS 不改。
- **app/lib/ui/icons.dart**：加 `sun`。
- **测试**：设置读写、阅读页在各种时机设的亮度、外观面板；Android 模拟器上实际看亮度变化。
