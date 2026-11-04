## Why

2026-11-03 用户从网址导入 `…coding.net/…/huahuoheji.json`，预览显示「跳过 1 个，第 1 项：缺少书源地址」。实际原因是这个网址已经要求登录，服务器用 HTTP 200 返回了一段错误 JSON（`{"msg":{"user_not_login":"用户未登录"},…}`），根本不是书源。提示把用户引向「书源写错了」，看不出是链接失效。

对照官方 Legado 3.25（反编译 APK）、legado-E、legado-with-MD3 三份导入代码，还缺两种通行的导入写法：`{"sourceUrls":[…]}` 网址列表、网址末尾的 `#requestWithoutUA`。三者在「内容里一个书源都没有」时都整份报错，不会逐项列出「缺少书源地址」。

## What Changes

- 导入内容里**一个可用书源都没有**时，不再显示预览，整份报一句话的原因：
  - 内容是订阅源（条目有 `sourceUrl`、没有 `bookSourceUrl`）：「这是订阅源，不是书源，暂不支持订阅源」
  - 空数组：「内容里没有书源」
  - 其它（包括不是合法 JSON）：「不是书源。内容开头：」加上内容开头 100 个字符（连续空白合并成一个空格）
- 支持 Legado 的网址列表 `{"sourceUrls":["网址1","网址2"]}`：逐个下载这些网址，各自按书源 JSON 解析，合并成一次预览。只展开一层（和官方 Legado、legado-E 一致）。单个网址下载失败或不是书源时，在预览的跳过列表里写明网址和原因，其它网址照常导入。
- 下载网址时支持 `#requestWithoutUA`：去掉这个标记，请求不带 User-Agent。不带标记时用和书源请求相同的默认 User-Agent（`defaultUserAgent`，原来是 Dart 的默认值）。替换规则从网址导入时同样生效（两者共用 `downloadText`）。
- 数组里混有订阅源条目时，跳过原因写「是订阅源，不是书源」，不再写「缺少书源地址」。
- 部分条目缺 `bookSourceUrl` 的混合内容，**保持**逐项跳过、其余照常导入（三个 Legado 都是整份拒绝，这里有意不同：能导入的部分导进来对用户更友好）。
- **不做**：
  - 压缩包响应（`application/zip`）：要引入解压依赖，书源网站基本不用。
  - `yuedu://`、`legado://` deep link：要改 Android 和 iOS 工程配置，单独做。
  - 导入时「保留原名、原分组、原启用状态」等选项。
  - 替换规则的 `sourceUrls`。
  - 嵌套的网址列表（列表里的网址又是列表）：按「内容里没有书源」处理。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `book-source`：「载入 Legado 书源 JSON」加上网址列表；「跳过无效条目」加上订阅源这个原因。
- `source-management`：「导入书源」加上整份报错的三种原因、网址列表的下载和预览、`#requestWithoutUA` 和默认 User-Agent。

## Impact

- **rule_engine**：`book_source.dart` 的 `loadBookSources` 识别 `sourceUrls`，`BookSourceLoadResult` 新增 `sourceUrls`；新增订阅源的跳过原因常量；`rule_engine.dart` 导出 `defaultUserAgent`。
- **app**：`import_text.dart` 的 `downloadText` 处理 `#requestWithoutUA` 和默认 User-Agent；`source_import.dart` 的 `previewImport` 改成异步，负责下载网址列表和整份报错；`source_list_page.dart` 跟着改调用。
- **测试**：`book_source_test.dart`、`source_import_test.dart`、`source_list_page_test.dart`。
- **数据**：不改表结构，不影响已导入的书源。
