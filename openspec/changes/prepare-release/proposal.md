## Why

PRD 第七节的前 7 步都已完成，只剩第 8 步：三个平台的真机测试与发布。到现在为止，所有验证都在模拟器和这台 Mac 上做，有三件事还没做：

- 第六节的性能和稳定性指标要在 Android 中端真机上测，还一次都没测过。
- 还发不出能给用户装的包：
  - Android release 包用的是 debug 签名，每台开发机的 debug 密钥都不一样，用户装上之后无法升级。
  - iOS 没有打过 IPA，macOS 没有打过 dmg。
  - 三个平台的图标都是 Flutter 默认的图标，macOS 上 app 名称显示为 `novel_reader`。
- 「同时 32 个连接」在手机网络上表现如何，模拟器上测不出来。

## What Changes

- **app 的名称和图标**：
  - 三个平台都显示「小说阅读」。macOS 现在显示 `novel_reader`，要改过来。
  - 新画一个图标，源图入库，三个平台各尺寸的图标都从源图生成。
- **Android 签名**：
  - 新建一个 release 密钥，放在仓库外面。密钥和密码都不入库。
  - 有密钥时，release 构建用它签名；没有密钥时，仍用 debug 签名，这样贡献者也能 `flutter run --release`。
  - 打包脚本会核对 APK 的签名证书。不是 release 密钥签的，脚本直接报错退出。
- **打包脚本**：在这台 Mac 上一次打出三个平台的发布包，检查完放进 GitHub Releases 的草稿。草稿由用户确认后再发布：
  - Android：只打 arm64-v8a 一个 APK，检查大小不超过 20MB。
  - iOS：未签名的 IPA，用户自己签名后安装。
  - macOS：dmg，里面的 app 只做 ad-hoc 签名。
- **版本号**：
  - 第一版是 0.1.0，tag 为 `v0.1.0`。
  - pubspec 加上构建号，以后每次发布都递增，保证 Android 能覆盖升级。
- **安装说明**：README 新增「安装」一节，写明三个平台怎么装：
  - Android：允许安装未知来源的应用。
  - iOS：用 AltStore、Sideloadly 等工具自签。
  - macOS：首次打开时被系统拦下怎么办。
- **真机测试**：按 PRD 第六节逐条验收，结果记在 tasks 里，并据此校准 PRD 里的数字。设备：
  - Android 中端真机
  - iPhone SE（第二代）
  - 这台 Mac
  
  验收项：
  - 端到端走查
  - 冷启动
  - 打开已缓存章节
  - 翻页帧率
  - 2000 章目录
  - 200 个书源搜索
  - APK 体积
  - 连续阅读 1 小时
  
  另外在手机网络下测一次搜索，决定 32 个连接的上限要不要调。
- **不做**：
  - CI。
  - Apple 的正式签名和公证。
  - 上架任何应用市场。
  - Windows、Linux。
  - 真机测试中发现的功能或性能问题，这个 change 只记录并报告。每个问题先和用户确认怎么处理，修复另开 change。只有调整搜索并发上限这一个常量算在本 change 里。

## Capabilities

### New Capabilities

- `release`：发布包，包括平台、文件命名、签名和体积；版本号和构建号；app 名称和图标；安装说明。

### Modified Capabilities

（无。关于页「版本号与安装包的版本一致」的要求不变，由 `release` 保证安装包里的版本号来自 pubspec。）

## Impact

- **代码与配置**：
  - `app/pubspec.yaml`：版本号加构建号；新增 dev 依赖 `flutter_launcher_icons` 和它的配置。
  - `app/android/app/build.gradle.kts`：release 签名读 `app/android/key.properties`。这个文件已被 `.gitignore` 忽略。
  - `app/macos/Runner/Info.plist`：显示名称改为「小说阅读」。
  - 三个平台的图标资源，都由工具生成。
  - 新增 `app/tool/release.sh`：打包、检查、建 GitHub Releases 草稿。
  - 可能调整 `app/lib/online/source_engine.dart` 里的 `networkLimit`，取决于手机网络下的测试结果。
- **新增文件**：
  - 图标源图，放在 `design/` 下。
  - 新增一个集成测试，测 2000 章目录打开的耗时。
- **仓库外的东西**：
  - release 密钥：放在 `~/.novel-reader/`，由用户备份。密钥丢了，以后发的包就不能覆盖安装了。
  - GitHub Releases：脚本只建草稿，草稿只有仓库成员看得到。但安装包会上传到 GitHub，所以运行脚本前要先问用户；发布草稿由用户自己点。
- **文档**：
  - README：「安装」一节；release 构建一节改掉「暂用 debug 签名」的说法。
  - PRD：第三节的「现状」、第六节的数字、第七节第 8 步。
