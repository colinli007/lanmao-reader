## Why

PRD（`docs/产品需求-第一版-2026-10-18.md`）定的第一版平台是 Android、iOS、macOS，其中 Android 是主要的发布渠道（GitHub Releases 发 APK）。app 目前只有 iOS 和 macOS 工程，Android 只在 spike 里验证过引擎。PRD 的开发顺序把它放在第一步：先把平台补齐，后面的分页排版、设置、备份等功能就能在三个平台上同时验证，不用到最后再补。

## What Changes

- `app/` 增加 Android 平台（applicationId `dev.novelreader.app`，应用名「小说阅读」），只构建 64 位（arm64-v8a，模拟器另加 x86_64），不出 32 位包。
- release 构建声明网络权限：Flutter 模板只在 debug、profile 的 manifest 里有 INTERNET，release 包会连不上网。
- 从文件导入书源时，Android 上把 MIME 识别不出的文件（`application/octet-stream`）也列为可选：下载来的书源文件在 Android 上常被识别成这个类型，否则会是灰的选不了。内容是不是书源 JSON 仍由导入预览判断。
- debug 构建启动时点亮屏幕、显示在锁屏之上、运行期间不息屏，让集成测试在模拟器上稳定运行（Android 会冻结不在前台的 app）。release 构建不受影响。
- 现有的单元测试、widget 测试、端到端集成测试和真实书源走查在 Android 模拟器上全部跑通；量一次 release 包（arm64）的体积，对照 PRD 的 20MB。
- 不改变任何功能行为，所以没有规格变更（`skip_specs`）。

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
（无。只是增加一个平台，所有能力的行为要求不变。）

## Impact

- 代码：新增 `app/android/`；`app/lib/online/source_list_page.dart` 的文件类型过滤；README 的运行说明。
- 依赖：不新增 Dart 依赖。现有的 `file_selector`、`path_provider`、`drift_flutter`（sqlite3 原生库）、`quickjs_ng_ffi` 都支持 Android（quickjs 在 spike 的 Android 模拟器和真机上验证过）。
- 构建：需要 Android SDK 和 NDK（spike 已经在用）；release 签名暂用 debug 签名，正式签名留给发布那一步。
- 测试：Android 16 模拟器（arm64）。真机测试按约定推迟到第一版所有功能完成后统一做。
