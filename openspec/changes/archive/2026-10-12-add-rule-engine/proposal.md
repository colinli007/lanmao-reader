## Why

阻塞桥和 JS 引擎都已就位，但 app 还读不了任何一本书：缺的是把 Legado 书源变成「搜索结果、书籍详情、目录、正文」的规则引擎。按 `source-check` 对 3310 条书源的统计，不含 JS 的 A 类有 1515 条（45.8%）。只靠规则引擎就能跑通它们，而 JS 运行时（B、C 类）也要建在规则引擎之上，所以先做 A 类。

动手前要定的三个前置问题里，有两个规则引擎自己就会碰到：

- **正则停不下来。** A 类书源里 59% 用了 `##` 正则净化。Dart 的 `RegExp` 不能中断，遇到灾难性回溯，worker 只能被放弃，一直占着线程和 CPU。
- **Cookie 要跨 worker 共享。** 51% 的 A 类书源开启了 CookieJar。同一书源的请求可能落在不同 worker 上，Cookie 必须只存一份。

第三个问题（JS 作用域隔离）只和 JS 有关，留给 JS 运行时的 change。

## What Changes

- 新增包 `packages/rule_engine`，在 worker 里同步执行：
  - **书源载入**：解析 Legado 书源 JSON（单条、数组），读出请求配置和搜索、详情、目录、正文四组规则。
  - **规则取值**：JSoup 默认语法、`@css:`、JSONPath（`@json:`、`$.`）、XPath（`@XPath:`、`/` 开头）、AllInOne 正则（`:` 开头）；组合运算符 `&&`、`||`、`%%`；`##正则##替换` 净化；`@put` / `@get` 变量；`{{$.x}}` 这类内嵌规则。语义以 legado-with-MD3（commit `d1b488b`）为准。
  - **请求构造**：URL 模板（`{{key}}`、`{{page}}`、`<1,2,3>` 页码）、URL 后面的 JSON 选项（method、body、headers、charset 等）、书源 `header`、GBK 编码的搜索词和响应解码、重定向后的地址参与相对地址解析。
  - **四条链路**：搜索（含「搜索结果直接是详情页」）、详情、目录（含多页目录）、正文（含多页正文）。
  - **遇到 JS 时明确报错**：规则里出现 `@js:`、`<js>`、`{{JS 表达式}}`，或请求选项里有 `js`、`webView` 时，以「需要 JS 引擎」或「需要 WebView」错误结束，不静默返回错误结果。规则引擎为 JS 留好接入点，给下一个 change 用。
- **网络在主 isolate 上执行**：worker 通过阻塞桥发起 HTTP 宿主请求，主 isolate 用同一个客户端和 CookieJar 处理，以原始字节返回。所有 worker 共享这一份 Cookie，以后 JS 里的 `java.ajax` 也走同一条路。
- **可中断的正则**：`quickjs_ng_ffi` 新增正则接口，直接调用 quickjs-ng 自带的 libregexp。回溯过程会检查任务的中止标志，取消和超时能让正则停下。规则引擎里所有正则都走这个接口。
- **测试**：规则语义用手写的小样例测试（按 MD3 的行为逐条对照）；四条链路用录制的真实页面做固定样例测试。另有一个联网冒烟工具，对一批真实 A 类书源跑完整链路，报告各链路的成功数，只用来观察，不作为通过门槛。和 MD3 的批量差分测试另开 change。

不在范围内：JS 执行（B、C 类）、WebView、登录、发现页（`exploreUrl`）、书源调试界面、Cookie 和书源的持久化存储。

## Capabilities

### New Capabilities
- `book-source`：载入 Legado 书源 JSON，识别规则里需要 JS 或 WebView 的部分。
- `rule-syntax`：规则字符串的解析和取值，包括各种取值语法、组合运算符、正则净化和变量。
- `source-request`：根据书源和 URL 模板构造请求，在主 isolate 上执行并解码响应，跨 worker 共享 Cookie。
- `book-chains`：搜索、详情、目录、正文四条链路，包括翻页和「搜索结果直接是详情页」。

### Modified Capabilities
- `js-engine`：新增「可中断的正则匹配」。正则由 quickjs-ng 自带的 libregexp 执行，响应任务的中止标志。

## Impact

- 新增包：`packages/rule_engine`。依赖 `blocking_bridge`、`quickjs_ng_ffi`（正则）、`html`（HTML 解析），主 isolate 侧用 `dart:io` 的 `HttpClient`。JSONPath、XPath、GBK 编码表等组件的来源在 design.md 里决定。
- 修改：`packages/quickjs_ng_ffi` 的 C 胶水、ffigen 绑定和 Dart 封装，新增正则接口；现有接口不变。
- 修改：`spike/` 增加规则引擎的端到端验证；选型文档「下一步」第 3 条更新进度。
- 环境：本机 Flutter 3.32.4 / Dart 3.8.1，所有新依赖都要兼容这个版本。
