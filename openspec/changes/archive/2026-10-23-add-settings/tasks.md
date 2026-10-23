## 1. 存储层（storage/database.dart）

- [x] 1.1 `contentCacheStats()`：一次查询返回已缓存正文的章节数和 `SUM(octet_length(content))` 字节数（D1）。先确认宿主机测试用的 SQLite 支持 `octet_length`（3.43 起才有，开发机系统自带的是 3.43.2）。验证：`test/storage/database_test.dart` 新增用例：
  - 空表时结果是 0 章、0 字节
  - 两本书各写几章含中文的正文后，章节数正确，字节数等于各章正文 `utf8.encode` 长度之和
- [x] 1.2 `clearContents()`：先 `DELETE FROM contents`，再在事务外 `VACUUM`；VACUUM 失败时只记日志，不向上抛（D2）。验证：`database_test.dart` 新增用例：
  - 清除后统计为 0 章
  - books、chapters、阅读进度、sources、settings、source_kv、cookies 的行都不变（对应 app-storage「清除不影响书架和进度」「清除不影响书源级状态」）
  - 用文件数据库写入约 10MB 正文，清除后文件大小减少约 10MB（对应「磁盘空间被回收」）

## 2. 设置页（lib/settings/）

- [x] 2.1 大小格式化纯函数：1024 进位，按 B/KB/MB/GB 选单位，不足 1KB 显示整数字节，其余一位小数（D6）。验证：单元测试覆盖 0、1023、1024、1.5MB、GB 级的输出。
- [x] 2.2 `contentCacheStatsProvider`（autoDispose 的 FutureProvider）负责统计；清除中是「正文缓存」项自己的状态，清除后 invalidate 统计（D3）。验证：放在 2.3 的 widget 测试里一起覆盖。
- [x] 2.3 `SettingsPage`：
  - 「正文缓存」项显示「统计中」或「N 章 · 大小」
  - 「清除」按钮在 0 章或清除中时不可用
  - 点「清除」弹出确认，确认框里写明章节数，并说明之后需要重新联网
  - 「关于」项进入关于页

  验证：新建 `test/settings/settings_page_test.dart`，覆盖 settings spec 的「从书架进入设置」「显示章节数和大小」「没有缓存」「确认后清除」「取消不清除」「没有缓存时不可清除」。
- [x] 2.4 书架顶栏末尾加设置按钮（`Icons.settings_outlined`，tooltip「设置」）（D6）。验证：在 `bookshelf_page_test.dart` 里点击设置按钮后，能找到「正文缓存」和「关于」。

## 3. 关于页

- [x] 3.1 添加依赖：执行 `flutter pub add package_info_plus`（D4）。验证：`flutter pub get` 成功；`flutter build macos --debug` 和 `flutter build apk --debug --target-platform android-arm64` 都能编过。
- [x] 3.2 `AboutPage`（D5）：
  - 显示 app 名称（和 `MaterialApp.title` 共用一个常量）、版本号（`PackageInfo.fromPlatform()`）、GPL-3.0、源代码地址、免责声明
  - 点源代码地址复制到剪贴板，并弹出 SnackBar「已复制」
  - 「开源许可」调用 `showLicensePage`

  验证：新建 `test/settings/about_page_test.dart`，用 `PackageInfo.setMockInitialValues` 注入 0.1.0，覆盖 spec 的「显示版本和免责声明」「复制源代码地址」（用 mock 的 Clipboard channel 断言剪贴板内容）「查看第三方许可」。
- [x] 3.3 模块边界：确认 `lib/settings/` 不引用 `rule_engine`。验证：`test/module_boundary_test.dart` 通过。

## 4. 端到端与三端检查

- [x] 4.1 `integration_test/app_flow_test.dart` 在已有流程（加书架、读章节）之后补一段：
  - 进入设置页，确认显示的章节数大于 0
  - 清除并确认，显示 0 章
  - 回到书架打开这本书，停在原来的位置，并且当前章重新请求了正文（对应 app-storage「清除后重新请求网络」）

  验证：`-d macos` 和 `-d emulator-5554` 都通过。
- [x] 4.2 在 macOS、iOS 模拟器、Android 模拟器上各打开一次关于页。验证：
  - 版本号都是 0.1.0
  - 开源许可列表里有 drift、flutter_riverpod、quickjs_ng_ffi 等依赖
- [x] 4.3 全量测试：带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`。验证：全部通过，`flutter analyze` 没有新的警告。

## 5. 文档

- [x] 5.1 仓库根目录加 GPL-3.0 的 `LICENSE`（GNU 官方全文）（D7）。验证：文件存在，GitHub 能识别出协议。
- [x] 5.2 README：开头加免责声明，文字和关于页一致；目录表里 `app/` 的说明补上设置页（正文缓存、关于）。验证：通读一遍，和实现一致。
- [x] 5.3 PRD 4.7 节：「设置页」「关于页与免责声明」的状态改为已完成；第七节开发顺序的第 3 步标为完成。验证：通读一遍，和实现一致。
