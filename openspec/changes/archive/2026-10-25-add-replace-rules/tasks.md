## 1. 规则的解析和执行（packages/rule_engine）

- [x] 1.1 `ReplaceRule` 和 `loadReplaceRules(text)`（D2）：
  - 接受单个对象或数组，字段和缺省值按 replace-rules「规则的格式」的表
  - `timeoutMillisecond` 不大于 0 时按 3000
  - 缺 `id` 时生成
  - 跳过的项带序号和原因：不是对象、`pattern` 为空、正则不可用

  `replaceRuleError(pattern, isRegex)` 判断正则不可用：编译不了，或者末尾是没有转义的 `|`。从 `lib/rule_engine.dart` 导出。

  验证：新建 `test/replace_rule_test.dart`：
  - 「缺省值」场景
  - 「无法编译的正则被跳过」场景
  - 末尾 `|` 和 `\|` 的区别
  - 未知字段保留在 `json` 里
- [x] 1.2 `applyReplaceRule(env, input, pattern, replacement)`，以及任务工厂 `replaceTask`、`loadReplaceRulesTask`、`replaceRuleErrorTask`（D2、D3）。替换串不合法、正则编译不了时都返回原文。验证：`replace_rule_test.dart` 覆盖 replace-rules「执行替换」的这些场景：
  - 引用分组
  - `(?i)` 开头标志
  - 替换串引用不存在的分组时原样返回

  `worker_regex_test.dart` 加一个用例：`replaceTask` 用 `(a+)+b` 作用在 30 个 `a` 上、超时 300 毫秒，提交方收到 `TaskTimeoutException`，worker 没有被放弃。

## 2. 存储（app/lib/storage/database.dart）

- [x] 2.1 新表 `replace_rules(id, json, enabled)`，`schemaVersion` 改为 2，加 `MigrationStrategy`（D4）。读写方法：
  - `allReplaceRules`
  - `putReplaceRules`（`insertOrReplace`）：导入和新建、编辑都用它，同一个 id 整行替换
  - `setReplaceRuleEnabled`：一条
  - `deleteReplaceRule`：一条，界面上只从编辑页删除

  重新生成 `database.g.dart`。

  验证：`test/storage/database_test.dart` 新增用例：
  - 读写方法
  - 「升级后数据还在」：
    1. 用文件数据库写入书源、书、正文、设置。
    2. `DROP TABLE replace_rules`，再 `PRAGMA user_version = 1`。
    3. 关闭后重新打开。
    4. 断言原有数据都在，替换规则为空，可以写入新规则。
  - 「清除不影响替换规则」

## 3. 规则仓库和净化（app/lib/online、app/lib/library）

- [x] 3.1 `SourceEngine` 新增 `replace`、`loadReplaceRules`、`replaceRuleError`，`PoolSourceEngine` 用 1.2 的任务实现，`replace` 的超时取规则的超时时间（D2、D3）。`FakeEngine` 直接在当前 isolate 调用 rule_engine 的函数，能注入超时。验证：`test/online/source_engine_test.dart` 新增用例，`replace` 超时时抛出 `TaskTimeoutException`。
- [x] 3.2 `ReplaceRuleRepository`（D7）：
  - 启动时载入，按 (`order`, `id`) 排序
  - `import`：同一 `id` 以最后一次为准
  - `save`：新建时 `order` 取最大值加 1；`id` 取毫秒时间戳，冲突时取最大值加 1
  - `setEnabled`
  - `disable` 返回是否改变了状态
  - `delete`
  - `export`：用当前启用状态覆盖 `isEnabled`
  - `startServices` 和 `TestServices` 里创建，加 provider

  验证：新建 `test/online/replace_rule_repository_test.dart`，覆盖：
  - replace-rules「再次导入同一份规则」
  - 「导出后再导入」
  - 排序
  - 新建的规则排在最后
  - 重启后启用状态还在
- [x] 3.3 `BookContentSource.purify` 和 `Purified`（D6），`OnlineContentSource` 实现：
  - 按作用范围、排除范围、作用于正文或章节名挑出规则
  - 普通文本在主 isolate 替换，正则交给 `replace`
  - 执行每条正则前读它当前是否启用
  - 超时时跳过这条并调用 `disable`，返回真时把规则名放进 `disabled`
  - 其它错误时跳过这条

  验证：新建 `test/online/purify_test.dart`，覆盖 replace-rules 的这些场景：
  - 只作用于某本书
  - 排除某个书源
  - 删除广告
  - 普通文本里的特殊字符
  - 依次作用
  - 灾难性回溯：用 FakeEngine 注入超时，断言规则被停用，`disabled` 只出现一次（两章同时执行同一条规则）

## 4. 阅读页（app/lib/reader/reader_page.dart）

- [x] 4.1 `_formatted` 先取原文，再调用 `purify`，然后 `formatChapter`；`disabled` 不为空时弹 SnackBar「替换规则「名称」超时，已停用」。缓存仍写原文（D1）。验证：`test/reader/reader_page_test.dart` 新增用例，覆盖 reader「替换净化」的这些场景：
  - 打开章节时去掉广告
  - 改规则后不用清缓存：断言 `engine.calls` 里没有这一章的 content，数据库里的正文仍是原文
  - 替换章节名：章节名只显示一次
  - 规则超时：显示 SnackBar，章节照常显示

## 5. 管理页面（app/lib/online、app/lib/settings）

- [x] 5.1 抽出 `online/import_text.dart`（D7）：
  - 三种来源的菜单项
  - 选文件
  - 输入对话框
  - `downloadText`（由 `downloadSourceText` 改名）
  - `ImportException`

  `source_list_page.dart` 改用它，书源导入的行为不变。验证：`test/online/source_list_page_test.dart`、`source_import_test.dart` 原有用例全部通过。
- [x] 5.2 `replace_rule_list_page.dart`：
  - 列表：名称为空时显示替换规则
  - 启用开关
  - 没有规则时的提示
  - 导入菜单：预览新增、更新、跳过和原因，确认后写入
  - 新建、导出到剪贴板

  `settings_page.dart` 在「正文缓存」前加一项「替换净化规则」。

  验证：新建 `test/online/replace_rule_list_page_test.dart`，覆盖：
  - 粘贴导入的预览和写入
  - 关掉开关后立即停用并落盘（重启后仍是停用由 3.2 的仓库测试覆盖）
  - 不是 JSON 时显示原因
  - 导出的剪贴板内容

  `test/settings/settings_page_test.dart` 覆盖 settings「进入替换净化规则」，`test/bookshelf/bookshelf_page_test.dart` 覆盖「从书架进入设置」。
- [x] 5.3 `replace_rule_edit_page.dart`：
  - 表单项按 replace-rules「新建和编辑规则」
  - 保存前用 `replaceRuleError` 校验，替换规则为空或正则不可用时显示原因、不保存
  - 编辑时保留不在表单里的字段
  - 删除前确认

  验证：新建 `test/online/replace_rule_edit_page_test.dart`，覆盖：
  - 「新建规则」
  - 「正则写错」
  - 编辑后分组和超时时间不变
  - 删除

## 6. 端到端、性能和全量检查

- [x] 6.1 `integration_test/app_flow_test.dart`：
  - 本地服务器 `/c/1` 的正文末尾加一行「请记住本站域名」
  - 在打开第一章之前，从设置页粘贴导入一条去掉这句话的规则
  - 断言阅读页里没有这句话，数据库里缓存的正文仍有这句话

  验证：`-d macos` 和 `-d emulator-5554` 都通过。
- [x] 6.2 性能实测（Risks 第 1 条）：在 Android 模拟器上，用 100 条正则规则（都不匹配）对一章 10 KB 的正文执行 `purify`，测 10 次取中位数，结果记在这一项下面。验证：中位数不超过 100 毫秒。超过时停下来和用户商量是否按 Risks 里的办法改。

  测量脚本是 `integration_test/replace_rules_perf_test.dart`（profile 构建，用法写在文件开头）。2026-10-25 在 Android 模拟器（emulator-5554，API 36）上：
  - 正文 3219 字，UTF-8 约 10 KB
  - 预热一次后测 10 次，中位数 10.5 毫秒
  - 各次耗时：8、9、9、9、10、11、12、18、38、44 毫秒
- [x] 6.3 全量测试：
  - `packages/rule_engine` 跑 `dart test`
  - app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`
  - 跑 `flutter analyze`

  验证：测试全部通过，没有新的警告，`module_boundary_test` 通过。

## 7. 文档

- [x] 7.1 PRD 4.5 节「替换净化规则」的状态改为已完成，第七节第 6 步标为已完成。验证：通读一遍，和实现一致。
- [x] 7.2 README 目录表里 `app/` 的说明补上「替换净化规则」。验证：通读一遍，和实现一致。
