## Context

动机和范围见 proposal.md，行为要求见 `specs/release/spec.md`。

### 现状

- **版本号**：`app/pubspec.yaml` 里是 `version: 0.1.0`，没有构建号，Flutter 按构建号 1 处理。关于页通过 `package_info_plus` 读安装包里的版本。
- **Android**：
  - `build.gradle.kts` 的 release 用 `signingConfigs.debug`，留着模板的 TODO。
  - `.gitignore` 已经忽略 `key.properties`、`*.jks`、`*.keystore`。
  - README 里的 release 命令是 `flutter build apk --release --split-per-abi --target-platform android-arm64`，2026-10-18 打出来 10.1MB。
  - 主清单声明了 `INTERNET`。release 包能不能访问 `http://` 书源，还没有在 release 包上验证过，见 Risks。
- **iOS**：
  - bundle id 是 `dev.novelreader.app`，显示名「小说阅读」。
  - `DEVELOPMENT_TEAM = 43UAHZVRQY`，自动签名，真机调试可以用。
  - 没打过 IPA。
- **macOS**：
  - `PRODUCT_NAME = novel_reader`，`CFBundleName` 取 `$(PRODUCT_NAME)`，所以菜单栏和程序坞显示 `novel_reader`。
  - `CODE_SIGN_IDENTITY = "-"`，即 ad-hoc 签名。
  - Release 的 entitlements 已经有沙盒、`network.client` 和用户选择文件只读。
- **图标**：三个平台都是 Flutter 模板的默认图标。
- **测量工具**：
  - `integration_test/real_sources_test.dart`：走查和 200 个书源的搜索计时。
  - `integration_test/reading_soak_test.dart`：连续翻页，记录跳章耗时、帧耗时、RSS 和 Dart 堆，profile 构建。
  - `integration_test/replace_rules_perf_test.dart`：单项耗时的写法，用 `REPORT` 开头打印结果。
  - 冷启动和 2000 章目录还没有测量手段。
- **搜索并发**：`PoolSourceEngine` 的 `networkLimit = 32`，是构造参数的默认值，`startServices` 没有传这个参数。
- **本机工具**：
  - 有 `magick`、`hdiutil`、`gh`。
  - Android SDK 的 build-tools 里有 `apksigner`。
  - 没有 `rsvg-convert`、`inkscape`。

## Goals / Non-Goals

**Goals:**

- 一条命令完成发布：从干净的工作区出发，打包、检查、建草稿。检查不通过就停下，不会传上去一个签错的包或者超体积的包。
- 判断标准只用最直接的证据：
  - 签名对不对，看 APK 里证书的指纹。
  - 版本号有没有递增，看上一个 tag 里的 pubspec。
  - 体积看文件大小。
  
  不靠「脚本里传了什么参数」来推断。
- 真机测量的方法可以重复执行，结果用数字记录。下个版本还按同样的方法测，前后可以对比。

**Non-Goals:**

- 发布流程放进 CI。
- 自动更新、应用内检查新版本。
- 给用户下载的文件提供校验值（如 SHA256SUMS）。GitHub Releases 会显示每个文件的 SHA-256。
- iOS、macOS 上的性能指标。PRD 只要求在 Android 中端机上测。iOS 和 macOS 只走一遍走查，再做必要的人工检查。

## Decisions

### D1 图标：一份 SVG 源文件，用 `flutter_launcher_icons` 生成各尺寸

> 此节保留首次发布时的图标方案记录。2026-11-03 已改用 B5「月夜幻想」PNG 母图，旧 SVG 和未采用的候选图标已清理；现行素材及生成方法见 [design/README.md](../../../design/README.md)。

- **源文件**：
  - `design/app-icon.svg` 是唯一的源文件。
  - 用 `magick` 从它渲染出三张 1024×1024 的 PNG，和 SVG 一起入库：
    - `app-icon.png`：满版正方形，给 Android 和 iOS 用。这两个平台的系统会自己加圆角或遮罩。
    - `app-icon-macos.png`：圆角方块，四周留透明边。macOS 不会替 app 加圆角，按 Apple 的图标网格，主体约占画布的 824/1024。
    - `app-icon-foreground.png`：Android adaptive icon 的前景，透明底，图形缩在安全区里。
  - SVG 只画书，透明底；底色和外形在渲染命令里加，命令写在 `design/README.md`。
  - spec 里说的「同一份源文件」指这份 SVG。
- **生成**：用 `flutter_launcher_icons` 的配置写进 `pubspec.yaml`：
  - Android 生成 adaptive icon：前景用透明底的图形，背景用纯色。
  - iOS 去掉透明通道，App Store 规则不允许图标带透明通道，自签安装也沿用这条规则。
  - macOS 用 `app-icon-macos.png`。
- **图案**：纯色底上画一本翻开的书，线条简单，在小尺寸下也能认出来。先给用户看 1024 的渲染图，确认后再生成各尺寸。
- **备选**：用 `magick` 自己写脚本出各尺寸。没选，因为要自己维护 Android 的 `mipmap-*` 和 adaptive icon 的 XML，还有 iOS 和 macOS 的 `Contents.json`，正是这个工具替我们做的事。它只是 dev 依赖，不进安装包，所以不按运行时依赖的审查标准评估。

### D2 macOS 名称：改 Info.plist，不改 PRODUCT_NAME

> 此节保留首次发布时的命名方案。2026-11-03 按用户确认统一更名为「懒猫阅读」，三端包标识为 `dev.lanmaoreader.app`，Flutter 包名及 macOS 构建产物名改为 `lanmao_reader`；发布脚本同步打包为「懒猫阅读.app」。以下原始决策用于历史追溯。

- **做法**：
  - `macos/Runner/Info.plist` 里 `CFBundleName` 写成「小说阅读」，再加 `CFBundleDisplayName`，值也是「小说阅读」。
  - `PRODUCT_NAME` 保持 `novel_reader`。构建出来的仍是 `novel_reader.app`，打 dmg 时把它拷成 `小说阅读.app`。
- **为什么不改 PRODUCT_NAME**：它同时决定可执行文件名和构建目录。改成中文后：
  - Flutter 工具、CocoaPods、集成测试脚本都要处理非 ASCII 路径。
  - `flutter test -d macos` 这类日常命令的风险也变大。
  
  菜单栏和程序坞读的是 `CFBundleName`，Finder 显示的是 .app 目录名，两处都改到就够了。
- **签名会不会失效**：代码签名只覆盖 bundle 里的内容，不包括 .app 目录名，所以改名后 ad-hoc 签名仍然有效。

### D3 Android 签名：key.properties 存在就用 release 密钥，发布时核对证书指纹

- **密钥**：
  - 位置：`~/.novel-reader/release.jks`。
  - 参数：RSA 4096，有效期 30 年，别名 `release`。
  - 密码：随机生成。
- **`app/android/key.properties`**：内容是 `storeFile`（绝对路径）、`storePassword`、`keyAlias`、`keyPassword`，按 Flutter 文档的约定放在这个位置。它已经被 `.gitignore` 忽略，文件权限设为 600。
- **备份**：要备份两样东西，`release.jks` 和 `key.properties` 里的密码，最好放进密码管理器。完成后由用户确认已经备份。
- **gradle 的写法**：key.properties 存在时，新增 `signingConfigs.release` 并给 release 构建使用；不存在时，仍用 debug 签名。
  - 这个分支防的是贡献者或新开发机没有密钥的情况。这时 `flutter run --release` 和这次验证屏幕常亮用的 release 构建都还要能跑。
- **发布前核对**：`release.sh` 用 `apksigner verify --print-certs` 读出 APK 证书的 SHA-256 指纹，和脚本里写死的指纹比较，不一致就停下。
  - 指纹是公开信息，可以入库。它是「这个 APK 用的是那把 release 密钥」最直接的证据：
    - key.properties 丢了、gradle 退回 debug 签名，会被拦下。
    - 换了一把别的密钥，也会被拦下。
  - **备选**：只检查 key.properties 是否存在。没选，因为文件存在不代表签名用的是那把密钥。

### D4 版本号：pubspec 是唯一来源，构建号和上一个 tag 比

- **pubspec**：改成 `version: 0.1.0+1`。Flutter 会自动写到三个平台：
  - Android：versionName 和 versionCode
  - iOS、macOS：CFBundleShortVersionString 和 CFBundleVersion
- **发布前检查**：
  - 远端没有 `v<版本>` 这个 tag，也没有同名的 Release，包括草稿。草稿 Release 在发布之前不会建 tag，所以两样都要查。
  - 构建号比上一个版本 tag 里 `app/pubspec.yaml` 的构建号大，用 `git describe --tags --abbrev=0 --match 'v*'` 找上一个 tag。第一次发布没有上一个 tag，跳过这项。
- **备选**：用提交数当构建号。没选，因为构建号会和 pubspec 脱节，关于页、安装包和 tag 不一定一致。

### D5 打包脚本 `app/tool/release.sh`

用 bash 写，和 `packages/quickjs_ng_ffi/tool/build_host.sh` 一样。两种用法：

- `app/tool/release.sh`：只打包和检查产物，用来在发布前试打。
- `app/tool/release.sh --upload <说明文件>`：先做发布前检查，通过后打包、检查产物，最后建草稿 Release。

**发布前检查**（只在 `--upload` 时做，打包之前）：

- `git status --porcelain` 为空。
- `git fetch` 之后，HEAD 是 `origin/main` 的祖先，也就是这个提交已经推送。
- D4 的 tag 和构建号检查。
- `gh auth status` 通过。

**打包**：产物放在 `app/build/release/<版本>/` 下。

- **Android**：`flutter build apk --release --split-per-abi --target-platform android-arm64`，产物改名。
- **iOS**：
  - `flutter build ios --release --no-codesign`。
  - 把 `build/ios/iphoneos/Runner.app` 放进 `Payload/`，用 `ditto -c -k --keepParent` 打成 zip，扩展名改成 `.ipa`。
  - 用 `ditto` 是为了保留 framework 里的符号链接。
- **macOS**：
  - `flutter build macos --release`。
  - 在临时目录里放 `小说阅读.app`（见 D2）和指向 `/Applications` 的符号链接。
  - 用 `hdiutil create -format UDZO` 打成 dmg，卷名「小说阅读」。

**检查产物**：

- APK：
  - 证书指纹（见 D3）。
  - `unzip -l` 里 `lib/` 下只有 `arm64-v8a`。
  - 大小不超过 20,000,000 字节，按 1000 进位。Flutter 构建输出的大小按 1000 进位，PRD 里的「10.1MB」就取自那里，所以用同一个口径。
- IPA：`Payload/Runner.app/Runner` 是 arm64，并且包含 quickjs 的 framework。
- dmg：
  - `hdiutil verify` 通过。
  - 挂载后能看到 `小说阅读.app`。
  - app 里的 `CFBundleShortVersionString` 等于这次的版本。

**上传**：

- 命令：`gh release create v<版本> --draft --target <HEAD 的 sha> --title "小说阅读 <版本>" --notes-file <说明文件> <三个文件>`。
- 说明文件放在 `docs/发布说明/v<版本>.md`，打包前提交。内容：
  - 免责声明
  - 主要变化
  - README「安装」一节的链接
- 脚本运行后打印草稿的网址，由用户检查后发布。

### D6 真机测量方法

**设备**：

- Android 中端真机，通过 USB 或无线调试连接。
- iPhone SE（第二代）。
- 这台 Mac。

**书源文件**：放在开发机的 `python3 -m http.server` 上。

- Android：用 `adb reverse tcp:8765 tcp:8765`，真机直接访问 `127.0.0.1:8765`。关掉 Wi-Fi 走手机网络时，这条 USB 通道照样能用。
- iPhone：用 Mac 的局域网地址。

**各项指标的测法**：

| 指标 | 方法 | 构建 |
|---|---|---|
| 走查（三个平台） | `real_sources_test.dart` 加 `WALKTHROUGH_SOURCES` | debug |
| 冷启动到书架可操作 | 临时探针：书架第一次带着数据画完的那一帧之后调 `Activity.reportFullyDrawn()`；`am force-stop` 后 `am start`，从 logcat 的 `Fully drawn` 取耗时，10 次取中位数。测完删掉探针 | release |
| 打开已缓存章节、翻页帧率、连续 1 小时 | `reading_soak_test.dart`，`SOAK_MINUTES=60`：跳章耗时、FrameTiming 的 99 分位、RSS 和 Dart 堆的走势 | profile |
| 2000 章目录 | 新增 `integration_test/toc_perf_test.dart`（见下） | profile |
| 200 个书源搜索 | `real_sources_test.dart` 加 `BENCH_SOURCES`，先连 Wi-Fi 测，再走手机网络测 | profile |
| APK 体积 | `release.sh` 的检查 | release |

**为什么冷启动用 `reportFullyDrawn`**：要测的是从点图标到书架可以操作。

- `am start -W` 的 TotalTime 只算到第一个窗口画出来。对 Flutter 来说，那是启动主题，不包括 Dart 的启动和 `startServices`，数字会偏小。
- `reportFullyDrawn` 是 Android 自己为「真正可用」准备的信号，系统从启动 intent 开始计时，正好是我们要的这一段。
- 只是临时测一下，不留进产品代码，这和前几个 change 用临时探针的做法一样。

**2000 章目录**：`toc_perf_test.dart` 照 `replace_rules_perf_test.dart` 的写法：

- 准备：在内存数据库里建一本 2000 章的书，当前读到第 1500 章，用来覆盖「滚到当前章附近」。
- 测两个入口：
  - 阅读页菜单里点「目录」
  - 书架书籍的详情页里打开目录：要从数据库读 2000 行
- 计时：从点下去开始，到当前章那一行出现在屏幕上的那一帧为止。
- 次数：先预热一次，再测 10 次，用 `REPORT` 打印中位数和最大值。

**60fps 怎么判**：真机可能是 90Hz 或 120Hz，帧预算仍按 PRD 的 60fps 算，也就是 16.7ms。99 分位不超过 16.7ms 算通过，同时记下设备的刷新率。

### D7 搜索并发上限：只在手机网络更差时才改

- **怎么测**：同一部 Android 真机，同样 200 个书源，先连 Wi-Fi 连测两次，再关掉 Wi-Fi 用手机网络测，记下：
  - 总耗时
  - 九成书源结束时的耗时
  - 超时的书源数
- **噪声**：网站的状态本身会波动。Wi-Fi 下两次测出的超时数之差就是噪声，记为 N；N 小于 5 时按 5 算。
- **什么时候试 16**：只有手机网络下超时的书源数比 Wi-Fi 下多出 N 以上，才把 `networkLimit` 临时改成 16，在手机网络下再测一次。改成 16 后：
  - 如果超时数减少超过 N、总耗时不超过 60 秒，就把默认值改成 16，并更新 `PoolSourceEngine` 的注释。
  - 否则保持 32。
- **为什么先测噪声**：以前没有在同一组书源上重复测过失败数，波动有多大不知道。先量出来，才不会被噪声带着改常量。
- **备选**：按网络类型动态调整。没选，因为要多监听连接状态，第一版没有证据说明需要。

## Risks / Trade-offs

- **[release 包不能访问 http:// 书源]**
  - 现象可能是：Android 9 以上默认禁止明文 HTTP；或者 Flutter 的 `dart:io` 按平台策略报 "Insecure HTTP is not allowed by platform"。
  - 很多书源是 `http://`。以前所有联网验证都用 debug 或 profile 构建，release 包还没验证过。
  - 应对：第一项任务就在模拟器上装 release 包，导入一个 `http://` 书源搜一次。如果被拦，在主清单的 `<application>` 上加 `android:usesCleartextTraffic="true"`（书源都是用户自己导入的，不可能列出域名白名单），然后重新验证。
- **[iPhone 访问 Mac 的局域网地址被拦]** iOS 14 起访问局域网会弹窗请求权限，没有点允许时请求会失败。应对：第一次运行时在 iPhone 上点「允许」；如果连弹窗都没有，再给 debug 构建的 Info.plist 加 `NSLocalNetworkUsageDescription`。
- **[macOS 15 上右键「打开」不再放行]** macOS 15 起，未公证的 app 必须到「系统设置 → 隐私与安全性」里点「仍要打开」。应对：README 写这个步骤，同时给出 `xattr -dr com.apple.quarantine "/Applications/小说阅读.app"`。验证时先给 dmg 加上隔离属性，模拟从浏览器下载的文件，再按 README 操作一遍。
- **[IPA 自签能不能装上]** 用哪个自签工具、用哪个 Apple ID，都是用户的环境。应对：脚本只检查 IPA 的结构。用户用自己常用的工具签一次装到 iPhone 上，把结果记在 tasks 里。
- **[release 密钥丢失]** 密钥丢了，以后发的包都不能覆盖安装，用户只能卸载重装，书架会丢。应对：建好密钥后先停下，等用户确认已经备份，再往下做。
- **[真机指标不达标]** 按 proposal，本 change 不修。应对：把数字和现象记在 tasks 里，停下来和用户商量。修复另开 change，修完再回来接着验收。PRD 第六节的数字也在这时一起校准。
- **[soak 测试在真机上跑 1 小时]** 手机可能息屏，或者被系统杀到后台。应对：profile 构建是可调试的，`MainActivity` 会让它保持亮屏（add-android 里已有）。测试期间接着电源。

## Migration Plan

- 第一次发布，没有旧版本要迁移。
- 0.1.0 之前用户手里只可能有 debug 签名的开发包，没有对外发过，所以不考虑从 debug 签名升级上来。
- 回滚：草稿 Release 可以直接删掉。已经发布的版本有问题时，发一个构建号更大的修复版，不删已发布的 Release。
