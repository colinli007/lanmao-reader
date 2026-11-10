## Why

fix-explore-compat 复测大灰狼聚合书源时（2026-11-10），搜索已经通过，详情报「No host specified in URI data:;base64,…」。这个书源的书籍地址是 `data:;base64,<书籍信息的 base64>,{"type":"qingtian"}`，把书籍信息直接编进地址。

MD3（legado-with-MD3 d1b488b，`AnalyzeUrl.kt`）的做法：`getStrResponseAwait` 在选项 `type` 不为空时调 `getByteArrayAwait()`，后者先看 `urlNoQuery`（GET 请求去掉查询串的地址）是否以 `data:` 开头、匹配 `^data:.*?;base64,(.*)`，是的话把 base64 按 Android `Base64.DEFAULT` 解码，**不发请求**，正文是这些字节的十六进制。我们的 `SourceRequest.fetch()` 一律发请求，所以失败。

用户 2026-11-10 决定发布前修掉。

## What Changes

- **带 `type` 选项的 `data:` 地址不发请求**：详情、目录、正文等链路的请求（`SourceRequest.fetch()`），`type` 不为空且地址是 `data:…;base64,数据` 时，按 Android `Base64.DEFAULT` 解码，正文是字节的十六进制，响应地址是请求地址，和带 `type` 的网络响应一样。不带 `type` 的 `data:` 地址照旧按网络请求处理（MD3 也会失败）。
- **正文图片的 `data:` 解码和请求共用一份**：按同一个正则和 Android 解码，空白等字母表以外的字符跳过，和 MD3 一致（现在用的是 Dart 的严格解码）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `source-request`：「URL 选项」里 `type` 的说明补上 `data:` 地址。
- `book-chains`：「正文图片」的 `data:` 地址按 Android 规则解码。

## Impact

- `packages/rule_engine/lib/src/request/analyze_url.dart`：`data:` 地址的解码函数，`fetch()` 里的分支。
- `packages/rule_engine/lib/src/chain/chains.dart`：正文图片改用共用的解码函数。
- 测试：`analyze_url_test.dart` 或链路测试覆盖 `data:` 详情；`content_image_test.dart` 保持通过。用大灰狼聚合书源联网复测搜索 → 详情 → 目录 → 正文。
