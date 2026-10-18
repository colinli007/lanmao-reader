## 1. Android 工程

- [x] 1.1 在 `app/` 里 `flutter create --platforms android .`（只加 Android，不动已有文件），applicationId 和 namespace 设为 `dev.novelreader.app`，应用名「小说阅读」。验证：`git status` 里只新增了 `app/android/` 和必要的元数据改动；`flutter build apk --debug` 成功。
- [x] 1.2 网络权限（D2）：main manifest 加 INTERNET。验证：`flutter build apk --release --split-per-abi --target-platform android-arm64` 成功，用 `aapt dump permissions`（或 `apkanalyzer manifest permissions`）检查 release 包里有 INTERNET；只产出 `app-arm64-v8a-release.apk` 一个包。
- [x] 1.3 debug 构建保持前台（D3）：debug manifest 合并 `showWhenLocked`、`turnScreenOn`，`MainActivity` 在可调试时加 `FLAG_KEEP_SCREEN_ON`。验证：模拟器息屏（`adb shell input keyevent KEYCODE_SLEEP`）后执行 `flutter run -d emulator-5554`，app 点亮屏幕并显示在前台；release 包的 manifest 里没有这两个属性。

## 2. 适配

- [x] 2.1 文件导入的类型过滤（D4）：Android 上的 `XTypeGroup` 只列 `application/json`、`text/plain`、`application/octet-stream` 三个 MIME 类型，其它平台保持扩展名加 UTI（macOS 会把 MIME 换成 UTType，octet-stream 会放开所有文件）。选中的文件自己按 UTF-8 解码（Android 上的 XFile 是内存字节，它的 `readAsString` 按 Latin-1 解，中文书源名是乱码）。验证：widget 测试覆盖三个平台的过滤条件和中文解码；在模拟器上 `adb push` 一个 `.json` 和一个无扩展名（识别成 octet-stream）的书源文件到 Download 目录，「从文件导入」两个都能选中、导入后书源名正常显示，`.js`、`.mp3` 选不了（用 `adb` 的界面自动化操作模拟器，不碰开发机桌面）。
- [x] 2.2 界面检查（D5）：在模拟器上逐页截图（书架、书源、搜索、详情、目录、阅读页和阅读菜单、阅读设置），检查状态栏、导航栏、刘海有没有挡住内容，返回手势能逐页返回、阅读页返回时保存进度。验证：截图逐张看过，发现的问题修掉并补测试（能用 widget 测试覆盖的）。结果：状态栏、导航栏、手势条都没挡住内容；书源页、目录页、目录抽屉、阅读设置、阅读页、详情页、搜索页的系统返回逐页通过，阅读页返回时保存了进度。发现并修掉两处：从文件导入的中文书源名乱码（见 2.1）；阅读页暗主题下状态栏图标仍是深色、看不清，改成按正文背景色决定图标深浅（`AnnotatedRegion<SystemUiOverlayStyle>`，iOS 同样受益），补了 widget 测试。

## 3. 测试与体积

- [x] 3.1 端到端集成测试在模拟器上通过：`flutter test integration_test/app_flow_test.dart -d emulator-5554`。验证：命令通过；模拟器息屏状态下开始也能通过。
- [x] 3.2 真实书源走查在模拟器上通过（书源文件经 `http://10.0.2.2:<端口>/` 导入）：6 个 A、C 类书源走完详情、加书架、读两章，重启后从书架继续、刷新书架；记录 192 个书源的搜索耗时。验证：报告和 macOS、iOS 的结果一致（失败的书源逐个确认是网站问题），耗时写进选型文档。
- [x] 3.3 量 release 包体积：`flutter build apk --release --split-per-abi --target-platform android-arm64` 产出的 APK 大小，`--analyze-size` 看分布。验证：数字和最大的几项写进选型文档；超过 20MB 时在文档里记下原因，留给发布那一步处理。

## 4. 文档

- [x] 4.1 根 README 的 app 运行说明加上 Android（模拟器运行、集成测试、走查用 10.0.2.2、release 打包命令）；选型文档第三节的平台说明、第五节进度更新；PRD 平台表里 Android 的现状更新。验证：README 里的命令照着能跑通。
