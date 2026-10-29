# novel-reader

跨端开源小说阅读器，兼容 Legado（开源阅读 3.0）书源。纯 Flutter 实现。

约束：开源、完全免费、不上架应用市场；书源功能只放在不上架的社区版里。

**免责声明**：本软件不提供任何内容。书源由用户自行导入，通过书源获取的内容与本软件无关。

开源协议：[GPL-3.0](LICENSE)。

## 安装

从 [GitHub Releases](https://github.com/colinli007/novel-reader/releases) 下载对应平台的文件（`<版本>` 是版本号，如 `0.1.0`）：

| 平台 | 文件 |
|---|---|
| Android（64 位） | `novel-reader-<版本>-android-arm64.apk` |
| iOS | `novel-reader-<版本>-ios-unsigned.ipa` |
| macOS | `novel-reader-<版本>-macos.dmg` |

**Android**：

1. 在手机上打开下载的 APK。
2. 第一次安装时，系统会要求允许浏览器或文件管理器「安装未知应用」，在弹出的设置里打开，返回后继续安装。

以后的版本直接覆盖安装，书架、书源和设置都会保留。不要先卸载，卸载会删掉本机的所有数据。不支持 32 位 ARM 的手机。

**iOS**：IPA 没有签名，要用自签工具装到手机上，比如 [AltStore](https://altstore.io/)、[Sideloadly](https://sideloadly.io/)：

1. 按工具的说明，用自己的 Apple ID 给 IPA 签名并安装。
2. iOS 16 及以上，第一次要在「设置 → 隐私与安全性 → 开发者模式」里打开开发者模式。
3. 打开 app 前，可能要在「设置 → 通用 → VPN 与设备管理」里信任自己的 Apple ID。

用免费 Apple ID 签名的 app 7 天后会打不开，要用同一个工具重新签名。重新签名不会丢数据。

**macOS**：

1. 打开 dmg，把「小说阅读」拖到「应用程序」。
2. 第一次打开时，系统会提示 Apple 无法验证「小说阅读」，点「完成」。这是因为 app 没有做 Apple 公证。
3. 打开「系统设置 → 隐私与安全性」，在下面找到「已阻止打开“小说阅读”」，点「仍要打开」，输入密码。
4. 再打开一次 app，在弹出的对话框里点「打开」。

也可以在终端里执行下面这条命令，清除下载时加上的隔离属性，之后就能直接打开：

```bash
xattr -dr com.apple.quarantine "/Applications/小说阅读.app"
```

## 目录

| 路径 | 内容 |
|---|---|
| `app/` | 阅读器 app（社区版，Android、iOS、macOS）：书源管理、搜索、详情与目录、书架（封面宫格，长按换书源，进度按章节名对齐）、目录页（已缓存标记、正倒序）、阅读（分页排版：标点避头尾、两端对齐、章节之间连续翻页；翻页方式有覆盖、滑动、无动画、滚动四种；菜单分目录、进度、外观、排版四个面板，字号、首行缩进、左右边距用加减，行距、段距三个预设）、设置（书源，替换净化规则，兼容 Legado 的格式；阅读设置：跟随系统深色、屏幕常亮；查看和清除正文缓存；关于页）；数据存在本机 SQLite 里。书源相关的代码都在 `app/lib/online/`，书架、阅读器、存储层不依赖规则引擎 |
| `packages/quickjs_ng_ffi` | 执行书源 JS 的引擎：quickjs-ng 源码（固定在 v0.17.0）+ C 胶水层 + ffigen 生成的绑定 + Dart 封装。支持 JS 同步调用宿主函数、嵌套求值、超时和内存上限 |
| `packages/rule_engine` | 书源规则引擎：载入 Legado 书源，解析规则，执行搜索、详情、目录、正文四条链路，书源 JS 在 quickjs-ng 上执行，注入常用宿主 API；行为对齐 legado-with-MD3 |
| `packages/blocking_bridge` | 阻塞桥：worker isolate 池，任务可以同步等待主 isolate 的异步结果，支持截止时间、取消、故障恢复 |
| `packages/native_synchronization` | 从 dart-lang/labs 拷贝进来自己维护的阻塞原语（Mailbox） |
| `spike/` | 纯 Flutter 路线的前置验证 app 和集成测试 |
| `docs/` | 产品需求（第一版的范围和验收标准）、技术选型、复核报告 |

选型依据和验证结果见 [docs/技术选型与验证-2026-09-28.md](docs/技术选型与验证-2026-09-28.md)。

## 运行 app

```bash
cd app
flutter run -d macos            # 或 iOS 模拟器、Android 模拟器（-d emulator-5554）
dart run build_runner build     # 改了 lib/storage/database.dart 的表之后重新生成

# 单元测试和 widget 测试；其中落盘的测试要执行书源 JS，需要开发机上编出来的 quickjs 动态库（见下一节）
QUICKJS_NG_FFI_LIB=$PWD/../packages/quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib flutter test

# 端到端集成测试：本地 HTTP 服务器上的假书源，走完导入、搜索、详情、加书架、翻页阅读、滚动阅读
flutter test integration_test/app_flow_test.dart -d macos     # 或 -d emulator-5554

# 真实书源走查（联网，见文件里的说明）
flutter test integration_test/real_sources_test.dart -d macos --dart-define=WALKTHROUGH_SOURCES=<书源文件网址>

# Android release 包：只出 arm64-v8a 一个 APK（不支持 32 位 ARM）
flutter build apk --release --split-per-abi --target-platform android-arm64

# 发布包：三个平台的安装包，打完检查签名、ABI、体积和版本，产物在 build/release/<版本>/ 下
tool/release.sh                                          # 只打包和检查，不上传
tool/release.sh --upload ../docs/发布说明/v<版本>.md     # 先做发布前检查，再建 GitHub 草稿 Release
```

签名和版本号：

- Android release 包的签名密钥由 `android/key.properties` 指定，这个文件不入库。没有它时用 debug 签名，`flutter run --release` 照样能跑，但这样的包不能发布，`tool/release.sh` 会核对证书指纹。
- 版本号只写在 `pubspec.yaml` 里，格式是 `<版本>+<构建号>`。每次发布，构建号都要比上一次大，否则 Android 不能覆盖升级。
- app 图标的源文件和生成方法见 [design/README.md](design/README.md)。

Android 模拟器上：

- debug 构建启动时点亮屏幕、显示在锁屏之上、运行期间不息屏（Android 会冻结不在前台的 app），模拟器息屏时也能直接跑集成测试；release 包没有这些设置。
- 模拟器访问开发机用 `10.0.2.2`。真实书源走查的书源文件放在开发机的本地 HTTP 服务器上，例如在书源文件目录里执行 `python3 -m http.server 8765 --bind 127.0.0.1`，再传 `--dart-define=WALKTHROUGH_SOURCES=http://10.0.2.2:8765/<文件名>`。
- 模拟器的数据分区至少留 1GB 空闲：debug 包约 100MB（带 JIT 内核快照），空间低于系统门槛时装不上（`INSTALL_FAILED_INSUFFICIENT_STORAGE`）。

## 运行验证

```bash
# 引擎单元测试（开发机，不需要 Flutter 构建）
cd packages/quickjs_ng_ffi
./tool/build_host.sh
QUICKJS_NG_FFI_LIB=$PWD/build/host/libquickjs_ng_ffi.dylib dart test

# 规则引擎单元测试和固定样例回放（开发机，需要上面编出来的 quickjs 动态库）
cd packages/rule_engine
QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib dart test

# 阻塞桥单元测试（开发机）
cd packages/blocking_bridge
dart test

# 阻塞桥集成测试（macOS / Android / iOS）
cd spike
flutter test integration_test -d macos
flutter test integration_test -d emulator-5554

# 同一套集成测试的 AOT 构建（真机），另外输出 worker 的内存成本
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/spike_test.dart -d <设备>
```
