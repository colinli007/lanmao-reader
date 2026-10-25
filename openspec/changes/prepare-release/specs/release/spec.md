## Purpose

发布：每个版本在 GitHub Releases 上提供 Android、iOS、macOS 三个平台的安装包，说明怎么安装；保证用户能覆盖升级、看到的版本号和安装包一致，app 在三个平台上有统一的名称和图标。

## ADDED Requirements

### Requirement: 发布包
每个版本 SHALL 在 GitHub Releases 上提供下面三个文件，`<版本>` 是这个版本的版本号，如 `0.1.0`：

| 平台 | 文件名 | 内容 |
|---|---|---|
| Android | `novel-reader-<版本>-android-arm64.apk` | 只含 arm64-v8a，不含 32 位 ARM 和 x86；体积 MUST NOT 超过 20MB |
| iOS | `novel-reader-<版本>-ios-unsigned.ipa` | 未签名，用户自签后安装 |
| macOS | `novel-reader-<版本>-macos.dmg` | 打开后是「小说阅读」app 和「应用程序」文件夹的快捷方式，拖过去就能安装；app 只做 ad-hoc 签名，不做公证 |

Release 的 tag 是 `v<版本>`，指向打包时的提交。打包 SHALL 在工作区没有未提交的改动、并且这个提交已经推送时进行，否则拒绝打包。Release SHALL 先建成草稿，由维护者检查后再发布。

#### Scenario: 一个版本的三个文件
- **WHEN** 维护者为 0.1.0 打包
- **THEN** 得到 `novel-reader-0.1.0-android-arm64.apk`、`novel-reader-0.1.0-ios-unsigned.ipa`、`novel-reader-0.1.0-macos.dmg`，并且 GitHub 上出现 tag 为 `v0.1.0` 的草稿 Release，三个文件都在里面

#### Scenario: APK 超过 20MB
- **WHEN** 打出来的 APK 是 21MB
- **THEN** 拒绝打包，提示 APK 的大小和 20MB 的上限，不建 Release

#### Scenario: 有未提交的改动
- **WHEN** 工作区有未提交的改动，维护者开始打包
- **THEN** 拒绝打包，提示先提交

#### Scenario: 安装 dmg
- **WHEN** 用户打开 dmg，把「小说阅读」拖进「应用程序」，按安装说明放行后打开
- **THEN** app 正常启动，显示书架

### Requirement: Android 签名
所有发布的 APK SHALL 用同一个 release 密钥签名，使新版本能覆盖安装旧版本，书架、书源和设置都保留。打包时 SHALL 核对 APK 的签名证书；不是 release 密钥签的 APK MUST NOT 发布。

开发时没有 release 密钥也 SHALL 能构建 release 包（用 debug 签名），只是这样的包不能发布。

#### Scenario: 覆盖升级
- **WHEN** 用户装着 0.1.0，书架上有书，再安装 0.1.1 的 APK
- **THEN** 直接覆盖安装，不要求先卸载；书架上的书、书源和设置都还在

#### Scenario: 用 debug 签名打的包
- **WHEN** 打包时 APK 是 debug 密钥签的
- **THEN** 拒绝打包，提示 APK 不是 release 密钥签的，不建 Release

#### Scenario: 没有 release 密钥的开发机
- **WHEN** 开发机上没有 release 密钥，开发者执行 `flutter run --release`
- **THEN** 构建成功，app 正常运行

### Requirement: 版本号
版本号 SHALL 只在 `app/pubspec.yaml` 里写一处，格式是 `<版本>+<构建号>`。三个平台的安装包、关于页、Release 的 tag 和文件名都用这个版本号。每次发布的构建号 SHALL 比上一次发布的大，Android 靠它判断能否覆盖升级。tag `v<版本>` 已经存在时 SHALL 拒绝打包。

#### Scenario: 关于页的版本和安装包一致
- **WHEN** pubspec 里是 `0.1.0+1`，用户安装 0.1.0 的发布包，打开关于页
- **THEN** 关于页显示版本 0.1.0

#### Scenario: 版本已经发布过
- **WHEN** `v0.1.0` 已经存在，pubspec 里仍是 `0.1.0+1`，维护者开始打包
- **THEN** 拒绝打包，提示先改版本号

### Requirement: app 名称和图标
app 在三个平台上 SHALL 都叫「小说阅读」，显示在这些地方：

- Android 和 iOS 的桌面图标下面
- macOS 的菜单栏、程序坞和「应用程序」文件夹

三个平台的图标 SHALL 由同一份源文件生成，源文件入库。

#### Scenario: macOS 上的名称
- **WHEN** 用户在 macOS 上打开 app
- **THEN** 菜单栏第一项和程序坞的提示都是「小说阅读」，不是 `novel_reader`

#### Scenario: 图标不是 Flutter 默认图标
- **WHEN** 用户在任意一个平台上安装发布包
- **THEN** 桌面、程序坞上的图标是 app 自己的图标

### Requirement: 安装说明
README SHALL 有「安装」一节，说明从哪里下载、每个平台下载哪个文件、怎么安装：

- Android：需要允许安装未知来源的应用；以后的版本可以直接覆盖安装。
- iOS：需要自签，列出常见的自签工具；用免费 Apple ID 签名的 app 7 天后要重新签名。
- macOS：首次打开会被系统拦下，说明在「系统设置 → 隐私与安全性」里放行的步骤，以及用终端清除隔离属性的命令。

每个 Release 的说明 SHALL 包含免责声明、这个版本的主要变化和指向「安装」一节的链接。

#### Scenario: macOS 首次打开被拦下
- **WHEN** 用户第一次打开从 dmg 装的 app，系统提示无法验证开发者
- **THEN** 用户按 README「安装」一节的步骤操作后能打开 app

#### Scenario: Release 的说明
- **WHEN** 用户打开 v0.1.0 的 Release 页面
- **THEN** 能看到免责声明、主要变化和安装说明的链接
