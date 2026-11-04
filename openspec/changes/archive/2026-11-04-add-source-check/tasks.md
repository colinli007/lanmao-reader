## 1. 引擎和存储

- [x] 1.1 rule_engine `errors.dart`：`RuleException` 新增 `tocEmpty`、`contentEmpty` 两个消息常量，`chains.dart` 抛「目录为空」「正文为空」时用它们（D3）。验证：`dart test` 全部通过，不用改测试。
- [x] 1.2 `database.dart` 新增 `updateSourceJson(url, json)`；`SourceRepository.updateSource(BookSource)` 只更新这一项，位置和启用状态不变，通知监听者（D2）。验证：新用例覆盖更新后位置、启用状态不变，重启（重新载入）后还是新内容。
- [x] 1.3 `SourceEngine.bookInfo`、`content` 增加可选的 `batch`，`PoolSourceEngine` 有 `batch` 时经限流器提交；`FakeEngine` 跟着改（D4）。验证：现有测试全部通过。

## 2. 校验（app/lib/online/source_check.dart）

- [x] 2.1 `markCheckResult(json, failure)`：去掉旧标记、按失败原因加分组和注释（D2、D3）。验证：`source_check_test.dart` 覆盖 source-check「标记结果」的三个场景、原来没有这两个字段时不写、其余分组和注释段落顺序不变、已有的失效分组不重复。
- [x] 2.2 `SourceCheckController`（provider）：关键词规则、四步检查、文件类到详情为止、失败归类、16 个并发、单个 180 秒、进度、停止、进行中拒绝再次发起、每完成一个写回（D1、D3、D4）。验证：`source_check_test.dart` 用 `FakeEngine` 覆盖：通过、每一步失败的归类、搜索 0 本、没有搜索地址不发请求、文件类、超时（注入短超时）、书源自带关键词和被过滤的关键词、并发上限、中途停止、进行中再发起被拒绝。

## 3. 界面（source_list_page.dart）

- [x] 3.1 `icons.dart` 加 `ellipsisVertical`；选择栏加「更多」菜单（校验、导出），弹出关键词对话框（`showInputDialog` 移到 `ui/widgets.dart`，导入共用）；校验中在列表上方显示进度和「停止」。验证：widget 测试覆盖发起、进度、停止、进行中再点提示正在校验。
- [x] 3.2 筛选框改成受控，匹配名字、地址、分组、注释；校验结束时自动筛选「失效」并提示（D5）。验证：widget 测试覆盖 source-management「校验后自动筛选」和按分组、注释筛选。

## 4. 验证和文档

- [x] 4.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`，rule_engine `dart test`。验证：全部通过。

  结果（2026-11-03）：app 311 个通过（新增 `source_check_test.dart` 9 个、列表页 2 个），rule_engine 901 个通过，两边 analyze 都没有问题。
- [x] 4.2 Android 模拟器上用合集 1329 校验一遍：看进度、停止、自动筛选、批量停用。验证：截图给用户看，各失效分组的数量记在这一项下面。

  结果（2026-11-03，Android 模拟器 API 36，debug 包，关键词「我的」，320 个书源全选）：约 3 分钟跑完，进度条和「停止」正常；结束后筛选框自动变成「失效」并提示。通过 130 个；网站失效 111（其中连接被关 69、TLS 握手失败 18）、js失效 42（Java 互操作 `org`、`Packages`、`JavaImporter` 共 16，不支持的宿主 API 9，jsLib 对象形式 5）、搜索失效 34、搜索目录失效 2、搜索正文失效 1。另有「需要 WebView」10 个归在网站失效。
  走查时发现选择栏多了一个图标后标题被挤成「已…」，「校验」「导出」收进「更多」菜单后正常。
- [x] 4.3 PRD 4.1 节「书源校验」标为已完成并写明做法；README 同步。验证：通读一遍。
- [x] 4.4 用户确认后同步主规格并归档（在 redesign-minimal-ui 归档之后，本 change 的「书源列表」以它为基础）。验证：`openspec validate --strict` 通过。

  结果（2026-11-04）：用户确认后同步到主规格并归档。
