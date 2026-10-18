## Context

动机见 proposal.md。现状：

- `app/` 只有 iOS、macOS 工程（add-app-shell 时只建了这两个）。所有依赖都有 Android 实现；quickjs_ng_ffi 的 Android 构建（CMake + NDK）在 spike 里跑过 Android 16 模拟器和 Android 15 真机。
- spike 的 Android 配置里有两处不能照搬：INTERNET 权限只在 debug、profile 的 manifest 里（spike 从没打过 release 包）；点亮屏幕、锁屏上显示、不息屏在所有构建里都开着（spike 只是测试宿主）。
- 网络走 `dart:io`，不受 Android 的明文 HTTP 限制（network security config 只管 Java 侧的网络栈）；spike 已经在模拟器上验证过本地 HTTP。
- `file_selector` 的 Android 实现用 `ACTION_OPEN_DOCUMENT`，不需要存储权限；它把扩展名用 `MimeTypeMap` 换成 MIME 类型作为过滤条件（json → `application/json`，txt → `text/plain`），只认 MIME，不看文件名。
- 开发机是 Apple Silicon，模拟器是 arm64（`emulator-5554`，Android 16）。

## Goals / Non-Goals

**Goals:**
- Android 上的行为和 iOS、macOS 一致：现有的全部自动化测试和真实书源走查在 Android 模拟器上通过。
- release 包能直接联网使用，只含 64 位代码，体积对照 PRD 的 20MB 量一次。
- 测试专用的设置不进 release 包。

**Non-Goals:**
- 正式签名、发布流程（PRD 开发顺序的最后一步）。
- 应用图标、启动页设计（用模板默认的，以后随设计稿换）。
- Android 专有功能：音量键翻页、阅读时屏幕常亮等属于 PRD 的阅读 P1，跟着阅读功能做。
- 真机测试（推迟到第一版所有功能完成后）。

## Decisions

### D1 ABI：只出 64 位，靠构建命令指定，不写 abiFilters

release 包用 `flutter build apk --release --split-per-abi --target-platform android-arm64`，只出 arm64-v8a 一个 APK。开发时 `flutter run` 按连接的设备只编需要的 ABI（arm64 模拟器就是 arm64）。

备选：在 `build.gradle.kts` 里写 `ndk.abiFilters`。它和 Flutter 的 `--split-per-abi` 会冲突（Flutter 按 target platform 生成拆包，abiFilters 再过滤一遍，构建会报错或出空包），而且 x86_64 模拟器也会被一起挡掉。不支持 32 位是发布时的决定，放在发布命令里最直接；README 写明命令。

### D2 网络权限写进 main manifest

`<uses-permission android:name="android.permission.INTERNET"/>` 放在 `src/main/AndroidManifest.xml`。模板里 debug、profile 的那两份保留（Flutter 工具链依赖它们做调试连接），重复声明不影响合并。

### D3 debug 构建为集成测试保持前台

Android 会冻结不在前台的 app、限制它的外网（spike 上遇到过 `flutter test` 连不上 VM service、外网请求解析失败），模拟器息屏后就会这样。处理和 spike 一样，但只在 debug 构建里：

- `src/debug/AndroidManifest.xml` 给 `MainActivity` 合并 `android:showWhenLocked="true"`、`android:turnScreenOn="true"`（Android 8.1 起生效）。
- `MainActivity.onCreate` 在应用可调试时（`ApplicationInfo.FLAG_DEBUGGABLE`）加 `FLAG_KEEP_SCREEN_ON`。

release、profile 构建不可调试，不受影响。

备选：测试前在模拟器上执行 `adb shell svc power stayon true`。不改代码，但每台机器、每次重启模拟器都要记得执行，之前在 spike 上已经否决过这个办法。

### D4 文件导入的类型过滤：加上 `application/octet-stream`

Android 上的 `XTypeGroup` 只列 MIME 类型：`application/json`、`text/plain`、`application/octet-stream`，MIME 识别不出的文件也能选。macOS、iOS 保持原来的扩展名加 UTI，不变。选错了文件（不是书源 JSON）由导入预览报「不是书源 JSON」，和现在一样。

不能把 MIME 类型加进所有平台共用的那个 `XTypeGroup`：macOS 11 起 file_selector 会把 MIME 类型也换成 UTType（`UTType(mimeType:)`），`application/octet-stream` 换出来是 `public.data`，选择框会放开所有文件。所以按平台给两个 `XTypeGroup`，判断用 `defaultTargetPlatform`（widget 测试里能覆盖）。

选中的文件按 UTF-8 自己解码，不用 `XFile.readAsString`：Android 上 file_selector 返回的是内存字节的 XFile，cross_file 对这种 XFile 的 `readAsString` 忽略 `encoding` 参数、用 `String.fromCharCodes`（等于 Latin-1），中文书源名会变成乱码；macOS、iOS 返回的是路径，碰巧没事。和「从网址导入」一样用 `utf8.decode(bytes, allowMalformed: true)`，不是 UTF-8 的内容由导入预览报「不是书源 JSON」。

备选：Android 上不过滤（`*/*`）。所有文件都能选，图片、APK 也在列表里，不如只放宽到「识别不出类型」的文件。

### D5 测试在模拟器上的跑法

- 单元测试、widget 测试和平台无关，在开发机上跑（`flutter test`），不用重复。
- 端到端集成测试 `integration_test/app_flow_test.dart` 在模拟器上跑：假书源的 HTTP 服务器起在 app 自己的进程里（127.0.0.1），不需要改。
- 真实书源走查 `integration_test/real_sources_test.dart`：书源文件放在开发机的本地 HTTP 服务器上，模拟器访问开发机用 `10.0.2.2`，`--dart-define` 传 `http://10.0.2.2:<端口>/…`。README 补上这一点。
- 界面检查用 `adb exec-out screencap` 截模拟器的屏，只截模拟器、不碰开发机的桌面：首页、书源页、搜索页、详情、阅读页（Android 15 起强制全面屏，检查状态栏和导航栏有没有挡住内容）。

## Risks / Trade-offs

- [Android 15 起 targetSdk 35 强制全面屏，界面可能被状态栏、导航栏挡住] → 页面都用 Scaffold/AppBar，阅读页有 SafeArea；按 D5 截图逐页检查，挡住了再处理。
- [模拟器网络经过开发机的代理（Clash），外网偶尔不稳] → 走查只看「通过的书源能走完」和「失败的原因是网站问题」，和 iOS、macOS 一样；不稳的单项重跑。
- [release 包体积超过 20MB] → 先量；超了用 `--analyze-size` 看分布，在发布那一步处理（PRD 的体积目标是第一版的验收标准，不是这一步的）。
- [debug 构建不息屏，开发时耗电] → 只影响开发机上的模拟器和调试中的手机，可以接受。

## Migration Plan

新增平台，没有数据迁移。iOS、macOS 工程不动。
