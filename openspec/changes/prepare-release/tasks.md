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

- [x] 6.1 在 Android 真机上跑 `integration_test/app_flow_test.dart` 和 `real_sources_test.dart` 的走查（书源文件通过 `adb reverse` 访问）。验证：两个都通过；走查里失败的书源逐个确认是网站的问题，结论记在这一项下面。

  测试机（6.2 到 6.6 都用它）：Redmi Note 14 Pro（24090RA29C），天玑 7300（MT6878），12GB 内存，Android 15（API 35），1220×2712，120Hz。走 Wi-Fi 直连，不经过代理；Mac 那边是走代理的。

  书源文件：会话的临时目录被清掉了，重新生成了一份。全量书源 jsDelivr 上已经 404，改从 GitHub 的 release 分支下载 `sources/b778fe6b.json`（blob `8b86091…`，20987130 字节），用原来的脚本（`random.seed(1)` 抽 200 个，recorded14 取自 `packages/rule_engine/test/fixtures/recorded/`）。生成的两个文件，大小和之前那份一字节不差。

  结果（2026-10-27）：
  - app_flow：通过。
  - 走查：通过。搜索 13 个书源，耗时 30 秒，失败 4 个，都是网络层的问题，不是引擎的问题：
    - 不知加啥（`m.rulianshi.la`）连接被拒：在手机上 ping 这个域名，解析出来是 `127.0.0.1`，是这个网络的 DNS 把它屏蔽了。它是 6 个走查目标之一，所以这次只走了 5 本。
    - 红叶书斋（`m.shufahouse.com`）连接被对方重置；绾书文学（`api.wanshu.com`）15 秒连不上：都发生在 TCP 层，规则还没执行。
    - 腐小说超过 30 秒：网站慢。Mac 走代理时它能正常返回。
  - 5 个书源各读两章都通过；重启后书架 5 本都停在第 2 章；从书架打开后显示上次读到的那一章；刷新书架 5 本，13 秒，失败 0 本。
- [x] 6.2 冷启动：
  - 加临时探针，书架第一次带着数据画完之后调 `reportFullyDrawn()`
  - 用 release 构建冷启动 10 次，从 logcat 的 `Fully drawn` 取耗时，算中位数
  - 测完删掉探针
  
  验证：中位数不超过 2 秒；数字、机型和书架上的书数记在这一项下面。

  结果（2026-10-27，Redmi Note 14 Pro，release 构建）：通过，中位数 527ms。
  - 数据：在 Mac 上照 app 的表结构造了一个数据库，书架上 10 本书，每本 1000 章，读到第 101 章，没有封面地址，不联网；书源 192 个（random200 去重后）。先装 debug 包，用 `run-as` 把它放到 `files/novel_reader.sqlite`，再用 `adb install -r` 覆盖装上 release 包。release 包临时挪开 key.properties，用 debug 密钥签名，这样才能覆盖安装、保留数据。签名不影响启动耗时。
  - 10 次（另外预热一次 577ms）：498、508、511、524、527、527、529、543、569、575ms。中位数 527ms，最大 575ms。
  - `am start -W` 的 TotalTime 每次都和 `Fully drawn` 相同，说明 Flutter 画第一帧时书架已经有数据了：`startServices` 在 `runApp` 之前就做完了，书架查询也很快。
  - 探针已经删掉（`git checkout` 还原了 `bookshelf_page.dart` 和 `MainActivity.kt`）。
- [x] 6.3 新增 `integration_test/toc_perf_test.dart`（D6），先在 Android 模拟器上跑通，再在真机上跑 profile 构建。验证：
  - 阅读页目录和详情页目录的中位数都不超过 1 秒
  - 两个入口都确实停在第 1500 章附近：测试里断言当前章那一行在屏幕上
  - 数字记在这一项下面

  模拟器（2026-10-25，emulator-5554，profile 构建，411×914）：通过，三项都远低于 1 秒。
  - 阅读页点「目录」到第 1501 章出现：中位数 100.1ms，最大 102.2ms（包括抽屉滑出的动画）。
  - 打开详情页到「目录（2000 章）」出现：中位数 82.7ms，最大 84.3ms（包括从数据库读 2000 行）。
  - 详情页点「目录」到第 1501 章出现：中位数 37.2ms，最大 40.9ms。
  - 两个入口打开后，第 1501 章那一行都是选中状态。
  
  真机（2026-10-27，Redmi Note 14 Pro，profile 构建，逻辑分辨率 375×834）：通过。
  - 阅读页点「目录」到第 1501 章出现：中位数 88.6ms，最大 99.0ms。
  - 打开详情页到「目录（2000 章）」出现：中位数 66.5ms，最大 68.6ms。
  - 详情页点「目录」到第 1501 章出现：中位数 46.0ms，最大 62.8ms。
- [x] 6.4 `reading_soak_test.dart`，设 `SOAK_MINUTES=60`，profile 构建，测试期间接着电源。验证：
  - 不崩溃
  - 跳章耗时不超过 300 毫秒
  - 帧耗时的 99 分位不超过 16.7 毫秒
  - Dart 堆的保留量没有持续增长
  - 数字和设备刷新率记在这一项下面

  结果（2026-10-27，Redmi Note 14 Pro，120Hz，profile 构建，60 分钟）：没有崩溃，跳章耗时达标；帧耗时和原生内存要和用户商量（见 6.7）。
  - 158 轮，点了 7900 次，41.6 万帧。
  - 打开已缓存章节到第一页显示：中位 41.6ms，99% 148.6ms，最大 150.3ms（158 次）。达标（300ms）。
  - 帧（ms）：

    | | 中位 | 99% | 最大 |
    |---|---|---|---|
    | build | 0.9 | 15.7 | 81.0 |
    | raster | 3.8 | 6.7 | 16.8 |
    | 总耗时 | 6.6 | 20.0 | 107.0 |

    总耗时超过 16.7ms 的帧有 5738 个，占 1.4%。如果按任务写的「总耗时的 99 分位不超过 16.7ms」判断，不达标；如果按 Flutter DevTools 判断卡顿的口径（build 和 raster 各自和帧预算比，两者是流水线并行的），两项的 99 分位都在 16.7ms 以内，60fps 达标，但 120Hz 屏的帧预算只有 8.3ms，按 120Hz 看是不达标的。模拟器上 build 的 99 分位是 4.1ms，真机慢了约 4 倍，UI 线程是瓶颈。
  - Dart 堆（GC 后）：12.8MB → 15.0MB。增长最多的是测试框架记录的每次点击（`_LiveTestPointerRecord`、`Color`、`Offset` 各 8501 个），以及测试报告用的字符串。排版对象一直在 2 到 3 个 `ChapterLayout`、几十个画笔，没有累积。
  - 原生 malloc（scudo）：93.0MB → 133.8MB，涨了 41MB；RSS 328MB → 410MB。add-paged-reader 在模拟器上用对照组确认过，这一量级的增长主要来自阅读器以外（引擎、图形栈和测试框架）。真机上还没有跑过对照组。

  慢帧分析（2026-10-28，用户选「先查慢帧再定」）：临时在 soak 测试里给三种操作打 timeline 标记，用 `binding.traceAction` 加 `--endless-trace-buffer` 抓了 1 分钟（7898 帧，build 的 99 分位 15.9ms，和 1 小时的结果一致），抓完用 `git checkout` 还原了测试文件。
  - build 超过 8.3ms 的帧有 203 个，其中 89 个超过 16.7ms。145 个出现在点击翻页后的第一帧（离点击 3 到 15ms），这一帧的 PAINT 阶段是 19 到 21ms；跳章（49 个）和切换翻页方式（9 个）后的慢帧，在实际阅读里很少出现。
  - 按翻页方式分，每次翻页后 300ms 内最慢的那一帧：

    | 翻页方式 | 翻页 | 超过 16.7ms | 最慢一帧的中位 |
    |---|---|---|---|
    | 覆盖 | 50 | 1 | 12.4ms |
    | 滑动 | 50 | 37 | 19.2ms |
    | 无动画 | 50 | 44 | 19.0ms |

  - 原因：`PagePainter.paint` 通过 `ChapterLayout.painterFor` 拿每一段的画笔，画笔在第一次画到这一页时才创建，创建时还要当场整段排版、做两端对齐。`retainAround` 只留住前后各两页已经建好的画笔，不会提前建。滑动和无动画模式下，新的一页是在点击后的第一帧才第一次画，所以要现场建二十来个画笔；覆盖模式下，下一页压在当前页下面，翻页前就画好了。
  - 改法方向：翻页停下来以后，在空闲的帧里提前给前后相邻的页建好画笔，可以参考 `layoutInBackground` 分帧的做法。这属于优化，按 proposal 另开 change。

  对照组（2026-10-28，`SOAK_CONTROL=true`，30 分钟，同一台手机，用户选「跑 30 分钟对照组」）：原生内存的增长和阅读器无关。
  - 对照组只点中间开关菜单，不翻页、不跳章：88 轮，点了 4400 次，21.3 万帧。
  - 前 30 分钟对比：

    | | 正式测试 | 对照组 |
    |---|---|---|
    | scudo | 93.0 → 113.5MB（+20.5MB） | 90.2 → 107.4MB（+17.2MB） |
    | RSS | 328 → 373MB | 312 → 383MB |
    | 排版对象 | 2 到 3 个 `ChapterLayout`，不累积 | 一直 2 个 |

  - 对照组什么都不翻，原生内存照样涨了同样多，所以这部分增长来自引擎、图形栈和测试框架，结论和 add-paged-reader 在模拟器上的一致。Dart 堆的增长在对照组里也一样，来自测试框架记录的点击。
  - 对照组 build 的 99 分位是 6.0ms，正式测试是 15.7ms，印证了慢帧来自翻页。

  结论（2026-10-28）：没有崩溃，跳章耗时达标；原生内存的增长和阅读器无关；Dart 堆和排版对象不累积。帧耗时按任务原来的标准（总耗时 99 分位 ≤ 16.7ms）不达标，原因是滑动、无动画翻页时第一帧现场建画笔。用户决定不挡发布，记进 `docs/待优化-滑动和无动画翻页掉帧-2026-10-28.md`，以后另开 change 修改。
- [x] 6.5 ~~200 个书源搜索，profile 构建：~~（用户 2026-10-28 决定不做）
  - Wi-Fi 下测两次，算出噪声 N
  - 关掉 Wi-Fi，走手机网络测一次
  - 按 D7 决定要不要试 16，以及要不要改默认值
  
  验证：
  - 每次测量的总耗时、九成书源结束时的耗时、超时数都记在这一项下面
  - Wi-Fi 下总耗时不超过 60 秒
  - 如果改了默认值：`flutter test` 通过，再在手机网络下测一次确认

  不做（2026-10-28）：用户决定跳过。所以手机网络下同时 32 个连接的表现没有测，`networkLimit` 保持 32 不变；200 个书源搜索的耗时仍以 2026-10-25 在 macOS 和两个模拟器上测的约 30 秒为准。8.2 改 PRD 时要写明这一条没有在真机上测。
- [x] 6.6 真机上手动检查：
  - 屏幕常亮：系统设成 30 秒熄屏，打开设置后停在阅读页 1 分钟，屏幕一直亮；返回书架后，30 秒熄屏
  - ~~音量键翻页：真实按键覆盖翻页、菜单打开时调音量、关闭设置后调音量~~（已由 remove-volume-key-turn 删除，不用检查）
  - 覆盖升级：
    - 装 `release.sh` 打出的 0.1.0+1，加一本书到书架
    - 临时把构建号改成 2 再打一个包，直接 `adb install -r` 装上去
    - 测完构建号改回 1
  
  验证：每一条的结果都和 spec 一致，记在这一项下面；覆盖升级后书架、书源和设置都还在。

  进展（2026-10-28，Redmi Note 14 Pro，装的是 `release.sh` 打出的 0.1.0+1 release 包，release 密钥签名）：
  - 屏幕常亮：用户手工验证，没有问题。
  - 音量键翻页：功能已由 remove-volume-key-turn 删除（用户 2026-10-28 决定），不用检查。用户在删除后的 release 包上确认过：按音量键不翻页。
  - 覆盖升级：通过。手机上先装好 0.1.0+1（用现在的代码打的 release 包，release 密钥签名），用户加书、改了阅读设置并记下状态；临时把 pubspec 改成 0.1.0+2 打包（证书仍是 `d2a5aa10…`），`adb install -r` 直接覆盖，系统没有要求卸载。`dumpsys package`：versionCode 1 → 2，firstInstallTime 不变（13:56:01），lastUpdateTime 变成 14:44:33。用户打开 app 核对：书架、阅读进度、书源和设置都还在。pubspec 已改回 0.1.0+1。
  - 关于页仍然只显示「版本 0.1.0」，不显示构建号，用户确认不需要显示。
- [x] 6.7 如果 6.1 到 6.6 里有不达标的项：停下来，把数字和现象报告给用户，商量怎么处理。修复另开 change（Risks「真机指标不达标」）。验证：没有不达标的项；或者每个不达标的项都有用户确认过的处理办法，记在这一项下面。

  结果（2026-10-28）：只有一项不达标，已经有用户确认过的处理办法。
  - 6.4 帧耗时：滑动、无动画翻页每翻一页约掉一帧。用户决定不挡发布，记进 `docs/待优化-滑动和无动画翻页掉帧-2026-10-28.md`，以后另开 change 修改。
  - 6.5 用户决定不做；6.6 的音量键检查随功能删除（remove-volume-key-turn）不再需要。其余各项都达标。

## 7. iPhone 和 Mac

- [ ] 7.1 iPhone SE（第二代）上跑 `app_flow_test.dart` 和走查，书源文件通过 Mac 的局域网地址访问，按 Risks 处理局域网权限。验证：两个都通过，结论记在这一项下面。

  进展（2026-10-28，iPhone SE 第二代，iOS 26.4.1，有线连接，还没完成）：
  - debug 构建在 iOS 26 真机上一启动就 SIGABRT：iOS 26 不允许 JIT 在 RX 和 RW 之间切换内存权限，Flutter 3.35 以后才修。profile 和 release 是 AOT，不受影响，所以 iPhone 上的集成测试改用 `flutter drive --profile`。发布的 IPA 是 release 构建，不受影响。直接从桌面点开 debug 包也会退出，这是 iOS 14 起的限制（debug 包必须由 Flutter 工具或 Xcode 启动）。
  - profile 下 app_flow 一开始在「粘贴导入」失败，提示「缺少 JSON 值」：`enterText` 没把文字写进输入框。请 Fable 分析后确认了根因：`IntegrationTestWidgetsFlutterBinding` 不接管文字输入通道（`registerTestTextInput` 固定返回 false），`enterText` 用 -1 作输入连接编号，框架只在 assert 里放行 -1（`services/text_input.dart` 第 2053 到 2064 行），profile 去掉了 assert，文字就被丢掉了。Android、macOS、iOS 模拟器用的是 debug 构建，所以没有暴露。
  - 修复：`app_flow_test.dart` 和 `real_sources_test.dart` 开头调用 `binding.testTextInput.register()`，加了注释说明原因。
  - 修复后 app_flow 在 iPhone（profile）、Android 真机（debug）、macOS（debug，切到 ABC 输入法跑）上都通过。
  - 还没做：iPhone 上的走查，用户说另找时间单独测。
  - iOS 模拟器（2026-10-28，iPhone 17 Pro，debug 构建，用的是现在的代码）：app_flow 通过；走查通过，搜索 13 个书源用了 7 秒，失败 1 个（绾书文学，TLS 握手时连接被断开，网络问题）。6 个书源各读两章都通过，重启后书架 6 本都停在第 2 章，从书架打开后显示上次读到的那一章，刷新书架 6 本用了 33 秒，失败 0 本。
  - 中途发生过的情况：Xcode 停在调试会话里时，`flutter drive` 报「Timed out waiting for CONFIGURATION_BUILD_DIR to update」，退出 Xcode 后恢复；手机上有一个 Runner 进程 SIGKILL 也结束不了，没有影响后面的运行。
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
