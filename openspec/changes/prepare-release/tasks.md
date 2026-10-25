## 1. 先验证 release 包能不能联网（Risks 第 1 条）

- [x] 1.1 在 Android 模拟器上装 release 包（`flutter run --release -d emulator-5554`），导入一个 `http://` 的书源，搜一次。
  - 能搜出结果：不改，结论记在这一项下面。
  - 被拦下：在主清单的 `<application>` 上加 `android:usesCleartextTraffic="true"`，重新验证。

  验证：release 包里 `http://` 和 `https://` 书源都能搜出结果。

  结论（2026-10-25，emulator-5554，Android 16 / API 36，`flutter build apk --release` 装上后用 uiautomator 操作界面）：不用改。
  - 「从网址导入」从 `http://10.0.2.2:8765/http3.json` 取到书源文件，导入 3 个：`http://www.biduju.net/`、`http://m.rulianshi.la/`、`https://www.douyinxs.com/`。
  - 搜「douluo」，结束时共 57 本，有的书有 2 个书源。打开其中一本，书源是必读居（`http://www.biduju.net/`），详情和目录（34 章）都取到了。
  - 原因：Dart 的 `HttpClient` 直接用 socket 发请求，不经过 Android 的 Java 网络栈，所以不受 targetSdk 28 起默认禁止明文 HTTP 的策略限制。

## 2. app 名称和图标（D1、D2）

- [x] 2.1 画 `design/app-icon.svg`，用 `magick` 渲染出 1024×1024 的 `app-icon.png`（满版）和 `app-icon-macos.png`（圆角方块，四周留透明边）。验证：把两张图给用户看，用户确认后再做 2.2；用户要改就改完再给他看。

  结果（2026-10-25）：深绿底 `#2F5D50`，奶白色翻开的书，书页上有横线。另外渲染了 Android adaptive icon 的前景 `app-icon-foreground.png`。三张图和 48px、32px 的小尺寸预览给用户看过，用户确认「就用这个」。渲染命令写在 `design/README.md`。
- [x] 2.2 加 dev 依赖 `flutter_launcher_icons`，在 `pubspec.yaml` 里配好三个平台：
  - Android：adaptive icon，透明底的前景加纯色背景
  - iOS：`remove_alpha_ios: true`
  - macOS：用 `app-icon-macos.png`
  
  然后生成各尺寸的图标。验证：
  - Android 模拟器的桌面、iOS 模拟器的主屏幕、macOS 的程序坞上，看到的都是新图标，截图确认
  - `git status` 里只有图标资源和 pubspec 的改动

  结果（2026-10-25）：
  - Android 模拟器：桌面截图里是新图标，adaptive icon 正常裁成圆形。工具会在前景四周再加 16% 的内边距，所以前景图按 82% 渲染，书最终约占 56%。
  - iOS 模拟器：新装的 app 排在主屏幕第二页，simctl 没法滑动翻页，所以没截主屏幕，改为检查已安装 app 里的 `AppIcon60x60@2x.png`，确认是新图标。
  - macOS：构建产物里的 `AppIcon.icns` 是新图标。NSWorkspace 一开始返回旧图标，那是 LaunchServices 的图标缓存，用 `lsregister -f` 重新注册后就是新图标了。
  - flutter_launcher_icons 0.14.4 每次运行都会把 iOS 工程里的 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` 从 `YES` 错改成 `AppIcon`，已经还原，并在 `design/README.md` 里写明运行后要还原。
  - 改动：pubspec 和 pubspec.lock，三个平台的图标资源，Android 的 `mipmap-anydpi-v26/`、`drawable-*/`、`values/colors.xml`。
- [x] 2.3 `macos/Runner/Info.plist`：`CFBundleName` 写成「小说阅读」，加 `CFBundleDisplayName`，值也是「小说阅读」。验证：`flutter run -d macos` 后，菜单栏第一项和程序坞的提示都是「小说阅读」；`flutter test integration_test/app_flow_test.dart -d macos` 仍然通过。

  结果（2026-10-25）：用 System Events 读运行中的 app：菜单栏第一项是「小说阅读」，菜单项是「About 小说阅读」「Hide 小说阅读」「Quit 小说阅读」，窗口标题也是「小说阅读」。MainMenu.xib 里的 `APP_NAME` 由 AppKit 按 `CFBundleName` 替换，不用改。进程名仍是 `novel_reader`，那是可执行文件名，按 D2 不改。程序坞的提示等 4.3 装好 dmg 后再确认。app_flow 在 macOS 上通过（切到 ABC 输入法跑）。

## 3. 签名和版本号（D3、D4）

- [x] 3.1 用 `keytool` 生成 `~/.novel-reader/release.jks`：RSA 4096，有效期 30 年，别名 `release`，密码随机生成。写好 `app/android/key.properties`，权限设为 600。验证：
  - `keytool -list -v` 能读出证书，记下 SHA-256 指纹
  - `git status` 里看不到这两个文件
  - **停下**：把需要备份的文件和密码告诉用户，等用户确认已经备份后，再往下做

  结果（2026-10-25）：
  - `~/.novel-reader/release.jks`：PKCS12，RSA 4096，SHA384withRSA，别名 `release`，`CN=novel-reader, O=novel-reader`，有效期到 2056-10-25。目录权限 700，文件权限 600。
  - `app/android/key.properties`：权限 600，被 `app/android/.gitignore` 忽略。PKCS12 的 store 密码和 key 密码相同。
  - 证书 SHA-256 指纹：`D2:A5:AA:10:9C:3B:BD:CD:E3:75:1B:FA:29:0B:A9:58:79:10:3C:74:94:DE:B2:EF:BA:AD:46:BF:02:21:6A:47`
  - 用户 2026-10-25 确认已经备份。
- [x] 3.2 `build.gradle.kts`：`key.properties` 存在时给 release 构建用 `signingConfigs.release`，不存在时仍用 debug 签名。验证：
  - 有 key.properties 时打 release 包，`apksigner verify --print-certs` 的指纹和 3.1 记下的一致
  - 临时把 key.properties 挪开，`flutter build apk --release` 仍能成功，证书是 debug 的；验证完挪回来

  结果（2026-10-25，build-tools 36.0.0 的 apksigner）：
  - 有 key.properties：证书 `CN=novel-reader, O=novel-reader`，SHA-256 `d2a5aa10…02216a47`，和 3.1 一致。
  - 挪开 key.properties：构建成功，证书 `C=US, O=Android, CN=Android Debug`，SHA-256 `9e99d38a…aefa5d01`。key.properties 已经放回原处。
- [x] 3.3 `pubspec.yaml` 的版本改成 `0.1.0+1`。验证：
  - `aapt dump badging` 读出 versionName 0.1.0、versionCode 1
  - iOS、macOS 的 Info.plist 里 `CFBundleShortVersionString` 是 0.1.0、`CFBundleVersion` 是 1
  - 关于页显示「版本 0.1.0」

  结果（2026-10-25）：
  - APK：`versionCode='1' versionName='0.1.0'`。
  - iOS（`flutter build ios --release --no-codesign`）、macOS（`flutter build macos --release`）：Info.plist 里都是 0.1.0 / 1。
  - 模拟器装上用 release 密钥签名的 APK，关于页显示「小说阅读 / 版本 0.1.0」。原来装的是 debug 签名的包，签名不同，先卸载才装得上，所以模拟器上原来的数据清空了。

## 4. 打包脚本（D5）

- [x] 4.1 `app/tool/release.sh` 不带参数时：打出三个平台的包，放在 `app/build/release/0.1.0/`，然后检查产物：
  - APK：证书指纹，`lib/` 下只有 `arm64-v8a`，大小不超过 20MB
  - IPA：结构和架构
  - dmg：`hdiutil verify`、app 名称和版本

  验证：
  - 三个文件名和 spec「发布包」的表格一致，脚本输出每项检查的结果
  - 临时挪开 key.properties 再运行，脚本在 APK 证书那一步停下，提示不是 release 密钥签的；验证完挪回来
  - 临时把体积上限改成 5MB 再运行，脚本停下，提示实际大小和上限；验证完改回来

  结果（2026-10-25）：
  - 试打：退出码 0。产物：`novel-reader-0.1.0-android-arm64.apk` 10.3MB，`…-ios-unsigned.ipa` 25.2MB，`…-macos.dmg` 28.9MB。三项检查都通过：APK 是 release 密钥签名、只有 arm64-v8a；IPA 是 arm64、含 quickjs、版本 0.1.0；dmg 里是 `小说阅读.app`、版本 0.1.0、有「应用程序」快捷方式。
  - 挪开 key.properties：退出码 1，停在 APK 证书那一步，提示证书是 `9e99d38a…`（debug）。key.properties 已经放回。
  - 上限临时改成 5MB：退出码 1，提示「APK 是 10.3MB，超过 5.0MB 的上限」，提示里的上限按常量显示。上限已经改回 20MB。
  - 体积按 1000 进位，和 Flutter 构建输出的口径一致，design D5 已改。
  - 改过一个问题：macOS 自带的 bash 3.2 会把紧跟在 `$变量` 后面的全角标点当成变量名的一部分，所以中文前面的变量都写成 `${变量}`。
- [x] 4.2 `--upload <说明文件>`：
  - 发布前检查：工作区干净、HEAD 已推送、tag 和草稿 Release 都不存在、构建号比上一个 tag 大、`gh` 已登录
  - 检查通过后再打包，最后用 `gh release create --draft` 建草稿
  
  验证：
  - 工作区有改动时运行，在第一项检查停下，提示先提交
  - 有一个没推送的本地提交时运行，提示先推送；用 `git reset --soft HEAD~1` 撤掉这个临时提交，改动保留
  - 不会真的上传：这两种情况都在打包之前就停下了

  结果（2026-10-25）：
  - 工作区有改动：在当前工作区运行 `app/tool/release.sh --upload README.md`，退出码 1，提示「工作区有未提交的改动，先提交」。
  - 有没推送的提交：没有按原计划在 main 上提交再 `reset --soft`，改成在 scratchpad 里建一个临时 worktree（游离在 HEAD），把脚本和 pubspec 提交成一个临时提交。这样工作区是干净的，HEAD 又不在 origin/main 上。运行后退出码 1，提示「HEAD 还没推送到 origin/main，先推送」。测完删掉了 worktree，main 没有动。
  - 两种情况都在打包前就停下了，没有上传任何东西。tag 和草稿已存在时的检查，等 8.3 建好草稿后再验证。
- [ ] 4.3 在这台 Mac 上验证 dmg 的安装：
  - 给 dmg 加上 `com.apple.quarantine` 属性，模拟从浏览器下载的文件
  - 按 README「安装」一节的步骤，把 app 拖进「应用程序」，放行后打开
  
  验证：
  - 第一次打开被系统拦下，按步骤操作后能打开
  - 书架正常显示，能导入书源并搜索
  - 结果记在这一项下面；测完删掉 `/Applications/小说阅读.app`

  进展（2026-10-25，macOS 15.8，还没完成）：
  - 做过的：给 dmg 加上 `com.apple.quarantine`（`0083;…;Safari;…`）后打开；用 Finder 把 app 拷进「应用程序」，拷出来的 app 带上了同样的隔离属性；`spctl --assess` 判定为 `rejected`，签名是 `adhoc`。
  - 没复现：不管用 `open` 还是 Finder 打开，app 都直接启动了（跑在 App Translocation 的随机目录里），没有被拦。推测是因为 app 是在本机用 Xcode 编出来的（文件带 `com.apple.provenance`），系统不对本机开发工具产出的代码做首次打开检查，没有证实。所以 README 里放行的步骤在这台 Mac 上验证不了，要换一台没编译过这个 app 的 Mac。
  - 确认了的：运行中的 app，LaunchServices 显示名是「小说阅读」，程序坞的提示也是它（补上 2.3 留下的那一条）。
  - 已清理：删掉了 `/Applications/小说阅读.app`，推出了 dmg。

## 5. 文档

- [ ] 5.1 README：
  - 新增「安装」一节，内容按 spec「安装说明」写
  - 「运行 app」里的 release 命令改成说明签名的情况和 `tool/release.sh` 的用法，删掉「暂用 debug 签名」
  
  验证：通读一遍；4.3 按它操作能装上。
- [x] 5.2 写 `docs/发布说明/v0.1.0.md`：免责声明、第一版的主要功能、README「安装」一节的链接。验证：通读一遍，没有提到任何书源、站点名或订阅地址（PRD 第二节第 2 条）。

## 6. Android 真机（D6、D7）

- [ ] 6.1 在 Android 真机上跑 `integration_test/app_flow_test.dart` 和 `real_sources_test.dart` 的走查（书源文件通过 `adb reverse` 访问）。验证：两个都通过；走查里失败的书源逐个确认是网站的问题，结论记在这一项下面。
- [ ] 6.2 冷启动：
  - 加临时探针，书架第一次带着数据画完之后调 `reportFullyDrawn()`
  - 用 release 构建冷启动 10 次，从 logcat 的 `Fully drawn` 取耗时，算中位数
  - 测完删掉探针
  
  验证：中位数不超过 2 秒；数字、机型和书架上的书数记在这一项下面。
- [ ] 6.3 新增 `integration_test/toc_perf_test.dart`（D6），先在 Android 模拟器上跑通，再在真机上跑 profile 构建。验证：
  - 阅读页目录和详情页目录的中位数都不超过 1 秒
  - 两个入口都确实停在第 1500 章附近：测试里断言当前章那一行在屏幕上
  - 数字记在这一项下面

  模拟器（2026-10-25，emulator-5554，profile 构建，411×914）：通过，三项都远低于 1 秒。
  - 阅读页点「目录」到第 1501 章出现：中位数 100.1ms，最大 102.2ms（包括抽屉滑出的动画）。
  - 打开详情页到「目录（2000 章）」出现：中位数 82.7ms，最大 84.3ms（包括从数据库读 2000 行）。
  - 详情页点「目录」到第 1501 章出现：中位数 37.2ms，最大 40.9ms。
  - 两个入口打开后，第 1501 章那一行都是选中状态。
  
  真机还没测。
- [ ] 6.4 `reading_soak_test.dart`，设 `SOAK_MINUTES=60`，profile 构建，测试期间接着电源。验证：
  - 不崩溃
  - 跳章耗时不超过 300 毫秒
  - 帧耗时的 99 分位不超过 16.7 毫秒
  - Dart 堆的保留量没有持续增长
  - 数字和设备刷新率记在这一项下面
- [ ] 6.5 200 个书源搜索，profile 构建：
  - Wi-Fi 下测两次，算出噪声 N
  - 关掉 Wi-Fi，走手机网络测一次
  - 按 D7 决定要不要试 16，以及要不要改默认值
  
  验证：
  - 每次测量的总耗时、九成书源结束时的耗时、超时数都记在这一项下面
  - Wi-Fi 下总耗时不超过 60 秒
  - 如果改了默认值：`flutter test` 通过，再在手机网络下测一次确认
- [ ] 6.6 真机上手动检查：
  - 屏幕常亮：系统设成 30 秒熄屏，打开设置后停在阅读页 1 分钟，屏幕一直亮；返回书架后，30 秒熄屏
  - 音量键翻页：真实按键覆盖翻页、菜单打开时调音量、关闭设置后调音量
  - 覆盖升级：
    - 装 `release.sh` 打出的 0.1.0+1，加一本书到书架
    - 临时把构建号改成 2 再打一个包，直接 `adb install -r` 装上去
    - 测完构建号改回 1
  
  验证：每一条的结果都和 spec 一致，记在这一项下面；覆盖升级后书架、书源和设置都还在。
- [ ] 6.7 如果 6.1 到 6.6 里有不达标的项：停下来，把数字和现象报告给用户，商量怎么处理。修复另开 change（Risks「真机指标不达标」）。验证：没有不达标的项；或者每个不达标的项都有用户确认过的处理办法，记在这一项下面。

## 7. iPhone 和 Mac

- [ ] 7.1 iPhone SE（第二代）上跑 `app_flow_test.dart` 和走查，书源文件通过 Mac 的局域网地址访问，按 Risks 处理局域网权限。验证：两个都通过，结论记在这一项下面。
- [ ] 7.2 iPhone 上检查屏幕常亮：自动锁定设成 30 秒，打开设置后停在阅读页 1 分钟，屏幕一直亮；返回书架后按时锁屏。验证：结果记在这一项下面，补上 complete-reader-settings 里留到真机才能确认的那一条。
- [ ] 7.3 用户用自己常用的工具（AltStore、Sideloadly 等）给 4.1 打出的 IPA 签名，装到 iPhone 上。验证：能启动，显示书架，能导入书源并搜索；用的工具和结果记在这一项下面。
- [x] 7.4 macOS 走查：`real_sources_test.dart -d macos`。验证：通过。遇到 Caps Lock 断言时，先切到 ABC 输入法再跑，跑完切回来。

  结果（2026-10-25，macOS 15.8，书源文件 recorded14.json，跑之前切到 ABC，跑完切回搜狗拼音并恢复 Caps Lock）：通过。
  - 导入 14 个，走查时搜索 13 个书源，耗时 3 秒，没有失败。
  - 6 个书源（必读居、抖音小说、不知加啥、多看阅读①、得间小说、影书小说）各读两章，都通过。
  - 重启后书架上 6 本都在，停在第 2 章；从书架打开后，显示的是上次读到的那一章。
  - 刷新书架：6 本，耗时 39 秒，失败 0 本。

## 8. 收尾和发布

- [ ] 8.1 全量检查：
  - app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`
  - `flutter analyze`
  - `app_flow_test.dart` 在 `-d macos` 和 `-d emulator-5554` 上跑
  
  验证：全部通过，没有新的警告。

  中间一轮（2026-10-25，做完 1 到 5 组的代码改动之后）：`flutter test` 260 个通过，`flutter analyze` 没有问题，app_flow 在 emulator-5554 和 macOS（2.3）上都通过。等第 6 组可能的改动做完后，最后再跑一遍，那时再打勾。
- [ ] 8.2 PRD：
  - 第三节「现状」写实测的结果：APK 大小、签名方式、IPA、dmg
  - 第六节的数字按第 6 组的实测校准，写明机型和日期
  - 第七节第 8 步标为已完成
  
  验证：通读一遍，和 tasks 里记录的数字一致。
- [ ] 8.3 等用户要求「提交并推送」后，先问用户确认，再运行 `app/tool/release.sh --upload docs/发布说明/v0.1.0.md`。验证：
  - 脚本打印出草稿的网址
  - 草稿里有三个文件，文件名和大小与本机 `app/build/release/0.1.0/` 下的一致
  - 再运行一次 `--upload`，在「草稿 Release 已存在」那一项检查停下（spec「版本已经发布过」）
  - 草稿由用户检查后自己点发布
