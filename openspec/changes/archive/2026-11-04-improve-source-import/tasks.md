## 1. 引擎（packages/rule_engine）

- [x] 1.1 `book_source.dart`（D3、D5）：
  - `BookSourceLoadResult` 新增 `sourceUrls`（默认空）
  - `loadBookSources`：顶层对象的 `sourceUrls` 是数组时只带回其中的字符串
  - 新增常量 `rssSourceSkipReason`，没有 `bookSourceUrl` 但有 `sourceUrl` 的条目用它
  - `rule_engine.dart` 导出 `defaultUserAgent`（D4）

  验证：`book_source_test.dart` 新增「网址列表」「混入订阅源」两个用例，原有用例不改，`dart test` 全部通过。

## 2. app（app/lib/online/）

- [x] 2.1 `import_text.dart` 的 `downloadText`（D4）：去掉 `#requestWithoutUA` 并不发 User-Agent；其余请求用 `defaultUserAgent`。验证：`source_import_test.dart` 新增用例，本地服务器分别收到 `defaultUserAgent` 和没有 User-Agent 的请求，带标记的请求路径里没有标记。
- [x] 2.2 `source_import.dart` 的 `previewImport` 改成异步（D1、D3）：
  - 一个可用书源都没有时按三种原因抛 `ImportException`；不是合法 JSON 也归到「不是书源。内容开头：」
  - 网址列表：并发下载、各自解析、按顺序合并，失败的网址和网址里的跳过条目写进跳过列表
  - `ImportPreview.skipped` 改成文字行

  验证：`source_import_test.dart` 覆盖 spec 里「下载到的是网站的错误信息」「订阅源」「网址列表」、空数组、`hello`，原有的「同一地址出现多次」用例照常通过。
- [x] 2.3 `source_list_page.dart`：`await previewImport`，跳过列表直接用 `preview.skipped`。验证：`source_list_page_test.dart` 里「不是书源 JSON」用例改成断言新的原因文字，其余用例不改，全部通过。

## 3. 验证和文档

- [x] 3.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`，rule_engine 跑 `dart test`。验证：全部通过，没有新的警告。

  结果（2026-11-03）：app 300 个通过（原来 295 个，新增 5 个），rule_engine 900 个通过（新增 2 个），两边 analyze 都没有问题。
- [x] 3.2 Android 模拟器上手工走一遍：导入 coding.net 那个网址看到「不是书源。内容开头：…用户未登录…」；导入 yckceo 一个书源合集网址正常预览；导入 yckceo 一个订阅源网址看到订阅源的提示。验证：截图给用户看，结果记在这一项下面。

  结果（2026-11-03，Android 模拟器 API 36，debug 包）：
  - coding.net 的网址：「无法导入」，原因是「不是书源。内容开头：{"msg":{"user_not_login":"用户未登录"},"data":{"account_type":"0"},"code":1000}」
  - yckceo 书源合集 `/yuedu/shuyuans/json/id/1330.json`：预览「新增 794 个，更新 0 个，跳过 0 个」，点了取消，没有写入
  - yckceo 订阅源 `/yuedu/rsss/json/id/1.json`：「这是订阅源，不是书源，暂不支持订阅源」
- [x] 3.3 PRD 4.1 节「从文件、网址、粘贴文本导入」的说明补上网址列表和 `#requestWithoutUA`；README 有导入说明的地方同步。验证：通读一遍。
- [x] 3.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-04）：用户确认后同步到主规格并归档。
