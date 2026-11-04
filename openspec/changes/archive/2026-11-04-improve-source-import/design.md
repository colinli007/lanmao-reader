## Context

导入书源分两步：`readImportText` 按来源（文件、网址、粘贴）拿到文本，`previewImport` 调 `loadBookSources` 解析并统计新增、更新、跳过，用户确认后写入。`loadBookSources` 在 rule_engine 里，是纯函数，不联网。

对照的三份实现（2026-11-03 查看）：
- 官方 Legado 3.25：`ImportBookSourceViewModel.importSourceAwait`（APK 反编译）。对象先读 `$.sourceUrls`，读到就逐个下载；数组只看第一项的 `bookSourceUrl`，为空整份报「不是书源」；网址导入只按数组解析；`#requestWithoutUA` 时把 UA 设成 `null`，拦截器再删掉这个请求头；没有 UA 时补 App 的 UA。
- legado-E（`8b87c5a`）：和官方相同。
- legado-with-MD3（`f5c45b7`）：先统一拿到文本再解析，`sourceUrls` 递归展开；每一项都必须有 `bookSourceUrl`，否则整份报错。

## Goals / Non-Goals

**Goals:**
- 下载到的不是书源时，用户能从提示里直接看出拿到的是什么。
- 支持 `sourceUrls` 和 `#requestWithoutUA` 两种通行写法。

**Non-Goals:** 见 proposal 的「不做」。

## Decisions

### D1：「是不是书源」按内容判断，不按 HTTP 状态码或 Content-Type

这次的错误内容是 HTTP 200、`application/json`，状态码和类型都说明不了问题；有没有 `bookSourceUrl` 才是对「这是不是书源」最准确的信号，三个 Legado 也都是看它。所以整份报错的条件是「解析后一个可用书源都没有」，与内容从哪来无关，文件和粘贴同样适用。

原因按内容再分三种，各自有明确的信号：
- 条目全是订阅源：每一项都有 `sourceUrl`（订阅源的标识字段，Legado 自动识别导入类型时也用它）。用户给的书源网站（yckceo）同时有书源和订阅源两类页面，容易拿错，单独说清楚。
- 空数组：没有条目。
- 其它：附上内容开头，让用户看到实际拿到的东西（这次就是「用户未登录」）。不是合法 JSON 的情况也归到这里，原来的「不是书源 JSON：解析器报错」对用户没有帮助。

开头取 100 个字符（按 Unicode 码点，不切断汉字和 emoji），连续空白合并成一个空格，避免格式化过的 JSON 只显示出缩进。

**备选**：在 `downloadText` 里看 Content-Type 或响应头（coding.net 有 `ret-status: 400`）。否决：只对个别网站有效，文件和粘贴也覆盖不到。

### D2：混合内容仍然逐项跳过

至少有一个可用书源时，行为不变：显示预览，跳过的条目列出位置和原因。三个 Legado 在这种情况下整份拒绝，这里不跟：混合内容多半是手工拼的，能导入的部分导进来更有用，而且原来的规格就是这样。

### D3：`sourceUrls` 的识别在 rule_engine，下载在 app

`loadBookSources` 保持纯函数：顶层是对象并且有数组类型的 `sourceUrls` 时，结果里只带这些网址（其中的字符串），不解析成书源。这和官方 Legado 的顺序一致：先认 `sourceUrls`，认不到再当单个书源。

下载和合并在 app 的 `previewImport`（改成异步）：
- 网址并发下载（`Future.wait`），结果按列表顺序合并；同一个书源地址出现多次时以最后一次为准（原有规则）。
- 每个网址的结果独立：下载失败、不是书源时，跳过列表里写「网址：原因」，原因的文字和整份报错相同；网址里的跳过条目写「网址 第 N 项：原因」。一个网址坏了不影响其它网址，这一点比三个 Legado 宽松（它们遇到第一个错误就整份失败），理由同 D2。
- 只展开一层。下载到的又是 `sourceUrls` 时，它对这个网址来说没有书源，按「内容里没有书源」记一条跳过。官方和 legado-E 也不递归；不递归就不会遇到列表互相引用的死循环，不用再加防护。
- 顶层是网址列表时，即使所有网址都失败，也显示预览（导入按钮置灰），因为内容本身是合法的网址列表，问题在各个网址，逐条列出更清楚。

`ImportPreview.skipped` 从 `SkippedSource` 记录改成已经拼好的文字行，因为来自网址列表的跳过项要带网址，位置信息不再只是一个下标。

### D4：`#requestWithoutUA` 和默认 User-Agent

`downloadText` 去掉网址末尾的 `#requestWithoutUA`，并把 `HttpClient.userAgent` 设成 `null`（`dart:io` 不发 User-Agent 头）。不带标记时用 rule_engine 的 `defaultUserAgent`：Legado 在请求没有 UA 时补的是 App 的 UA，`#requestWithoutUA` 的意思是「不要那个 UA」，所以默认值应该和书源请求一致，而不是 Dart 的 `Dart/x.y (dart:io)`。

`defaultUserAgent` 目前没有导出，在 `rule_engine.dart` 里用 `show` 只导出这一个常量。

### D5：订阅源的跳过原因用常量

`SkippedSource.reason` 是给用户看的文字，替换规则那边也是同样的写法。app 要判断「是不是全部是订阅源」，所以把这个原因定义成 rule_engine 里的公开常量 `rssSourceSkipReason`，app 和它比较，不写字符串字面量。

## Risks / Trade-offs

- 默认 User-Agent 从 Dart 改成桌面 Chrome，个别对 UA 敏感的书源托管站返回的内容可能变化 → 和 Legado 的行为一致，Legado 用户分享的链接本来就是在这个前提下能用的；真不行可以加 `#requestWithoutUA`。
- `sourceUrls` 列表很长时同时发出很多请求 → 实际的列表通常只有几个网址，不加并发上限。
