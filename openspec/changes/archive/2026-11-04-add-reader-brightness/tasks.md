## 1. 设置和平台通道

- [x] 1.1 `reader_settings.dart`：加 `brightness`（0.01 到 1，默认 0.4）、`brightnessFollowSystem`（默认 true），读写设置，读到越界的值时夹到范围内（D3）。验证：`reader_settings_test.dart` 覆盖默认值、读写、越界。

  结果（2026-11-04）：新增 1 个用例，读写用例加上这两项，9 个都通过。
- [x] 1.2 新增 `screen_brightness.dart`：`ScreenBrightness.set(double?)`，记住上一次的值、相同的不调用；`supported` 只在 Android、iOS 为真（D1、D2）。原生：Android `MainActivity.kt`、iOS `AppDelegate.swift` 的通道加 `brightness` 方法。验证：analyze 通过；平台上的效果在第 3 组验证。

  结果（2026-11-04）：`supported` 用 `defaultTargetPlatform` 判断，测试可以用 `TargetPlatformVariant` 覆盖；不支持的平台上 `set` 直接返回，阅读页不用自己判断。Android 的通道改成按方法名分派；iOS 用 `systemBrightness` 记下原来的亮度。

## 2. 阅读页和外观面板

- [x] 2.1 `reader_page.dart`：`_updateScreen()` 同时设亮度；离开时设回 `null`；亮度设置变化时更新（D1）。`test_app.dart` 加记录调用的假实现。验证：`reader_page_test.dart` 覆盖打开时、跟随系统时、退到后台和回来、改滑块、离开。

  结果（2026-11-04）：`_updateScreen()` 同时算常亮和亮度；监听的设置从 `keepScreenOn` 一项扩成三项。新增 3 个用例（含 macOS 不调用）。
- [x] 2.2 `icons.dart` 加 `sun`；外观面板主题上面加亮度一行，只在支持时显示，跟随系统时滑块不可用（D4）。验证：widget 测试覆盖拖动、切换跟随系统、不支持时不显示。

  结果（2026-11-04）：新增 2 个用例；滑块的语义标签是「亮度 N%」。

## 3. 验证和文档

- [x] 3.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`。验证：全部通过。

  结果（2026-11-04）：app 324 个通过，analyze 没有问题。
- [x] 3.2 Android 模拟器上走一遍：关掉跟随系统、拖到最暗和最亮，返回书架、退到后台再回来、重启后再打开。验证：截图给用户看；用 `dumpsys window` 看窗口的亮度值。

  结果（2026-11-04，Android 模拟器 API 36，debug 包）：书架上加了《斗破苍穹》来测。外观面板主题上面是太阳图标、滑块、「跟随系统」；跟随时滑块是灰的。关掉跟随、拖到最左显示「亮度 1%」，拖到最右「亮度 100%」，`dumpsys display` 的 `mBrightnessReason` 是 `override(...MainActivity)`，返回后变回 `manual`。用窗口参数 `sbrt` 看各个时机：阅读页 `sbrt=1.0`；退到后台没有 `sbrt`（恢复成系统的）；回到前台又是 1.0；返回书架没有；强制停止再打开，从书架进阅读页仍是 1.0。模拟器截屏拍不出背光变化，所以以窗口参数为准。注意：按 HOME 后要等切换动画结束（约 2 秒以上）才走到 onStop、恢复亮度，查得太早会看到旧值。测完把模拟器上的设置改回「跟随系统」。
- [x] 3.3 PRD 4.5 节「阅读页亮度」标为已完成；README 同步。验证：通读一遍。
- [x] 3.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。iPhone 上的效果按用户的安排放到最后的真机测试。

  结果（2026-11-04）：用户确认后同步到主规格并归档。
