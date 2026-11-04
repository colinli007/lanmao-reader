## 1. 存储

- [x] 1.1 `database.dart`：新表 `SearchKeywords`（`word` 主键、`usage`、`lastUsed`），schemaVersion 3，`from < 3` 时建表（D1）；方法 `useSearchKeyword(word, now)`、`watchSearchKeywords(filter)`（为空时按最后使用时间倒序，不为空时按包含过滤、次数倒序）、`deleteSearchKeyword(word)`、`clearSearchKeywords()`；重新生成 `database.g.dart`。验证：`database_test.dart` 覆盖记录和次数、两种排序、删除和清除、从 v2 升级后原有数据都在且能写入历史。

  结果（2026-11-04）：`like` 的过滤用 `escapeChar` 转义了 `%`、`_`、`\`，按字面包含（Legado 直接拼进 LIKE，输入 `%` 会匹配全部）。database_test 新增 2 个用例，17 个都通过。

## 2. 搜索页

- [x] 2.1 `search_page.dart` 改成有状态组件，输入框受控；最后一次是改输入框时显示历史，提交后显示结果；改输入框时停止搜索（D2）。提交和点历史词时记入历史（D3）；长按删一条，「清除」确认后删全部；没有历史时不显示这一块（D4）。验证：`search_page_test.dart` 覆盖 book-search「搜索历史」的六个场景（换书源不记历史在 `change_source_page_test.dart` 里断言）。

  结果（2026-11-04）：历史区域写成页面 State 的一个方法，点历史词直接改页面自己的输入框和状态，不往子组件传回调。新增 5 个 widget 用例。两处测试上的坑：存的时间精确到秒，同一秒里连着搜几次时先后不确定，按时间排序的用例先用固定时间写入历史；在假时间里 `await` drift 的 watch 流会一直等不到，测试里直接查表。

## 3. 验证和文档

- [x] 3.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`。验证：全部通过。

  结果（2026-11-04）：app 318 个通过，analyze 没有问题。
- [x] 3.2 Android 模拟器上走一遍：搜几个词，看排序、过滤、点击、长按、清除，重启后还在。验证：截图给用户看。

  结果（2026-11-04，Android 模拟器 API 36，debug 包，重新导入了合集 1329 的 320 个书源）：依次搜 doupo、douluo、doupo、santi，清空输入框后是 santi、doupo、douluo；输入 dou 后是 doupo（2 次）、douluo（1 次）；点 doupo 填进输入框并开始搜索；搜索中删掉一个字，结果区域换成历史；强制停止再打开，历史还在、doupo 排到最前；长按 douluo 删掉；「清除」弹出红色确认按钮，确认后整块不再显示。
- [x] 3.3 PRD 4.2 节「搜索历史」标为已完成；README 同步。验证：通读一遍。
- [x] 3.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-04）：用户确认后同步到主规格并归档。
