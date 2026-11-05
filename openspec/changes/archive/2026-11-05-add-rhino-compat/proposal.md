## Why

发现页走查时，合集 1329 里有书源因为 Rhino 专有的写法失败。按两份合集（文本书源 275 个、691 个）的全部规则统计：

- 直接用 Java 类的书源占 14%（38 个、94 个），其中用 `org.jsoup.Jsoup.parse` 的占绝大多数（34 个、75 个）。这类书源在搜索、详情、目录、正文里都可能失败，书源校验里的「js失效」大多是它。
- `[a,b]=>` 这种不带括号的解构箭头函数：12 个、18 个。Legado 3.25 的 Rhino 把 `=>` 前面的数组当成解构参数（`Parser.arrowFunctionParams`），QuickJS 按标准报语法错误。
- `source.getWebViewUA()`：2 个、6 个。

用户 2026-11-05 确认：这三类做；其余 Java 类（零散，每个只有几个书源用）和 jsLib 的 JSON 形式（文本书源里 0 个、4 个）先不做。

## What Changes

- **Jsoup**：JS 里可以用 `org.jsoup.Jsoup.parse(html[, 基准地址])`、`Jsoup.parseBodyFragment(html)`，`Packages.org.jsoup…` 也一样。结果是文档的元素包装对象，用现有的 jsoup 兼容实现（选择器、文本、属性）。
  - 基准地址让 `attr('abs:href')` 能转成绝对地址。
  - 元素补上书源里常用的 `data()`、`remove()`；元素列表补上 `remove()`（不带参数时从文档里删掉这些元素，带下标时和 Java 列表一样删掉一项）。
- **其它 Java 类**：`org.*`、`Packages.*` 下别的类，调用时以「不支持的宿主 API：类名」结束，和其它不支持的宿主 API 一样，代替现在含糊的「org is not defined」。
- **解构箭头函数**：执行书源 JS 之前，把 `[a,b]=>` 改写成 `([a,b])=>`。只改这一种形式，字符串、模板、注释、正则里的不动。
- **getWebViewUA**：返回一个 Android WebView 的 User-Agent，不再是不支持的宿主 API。

## Capabilities

### Modified Capabilities

- `source-js`：「Rhino 专有写法」改为：解构箭头函数改写后执行，Jsoup 可用，其余 Java 类以不支持的宿主 API 结束。
- `source-js-api`：「元素包装对象」加 `data()`、`remove()`；新增「Jsoup」；「不支持的宿主 API」去掉 `getWebViewUA`，新增「WebView 的 User-Agent」。

## Impact

- **packages/rule_engine/lib/src/js/**：`prelude.dart`（`org`、`Packages`、元素方法、`getWebViewUA`）、`host_api.dart`（`jsoup.parse` 等）、`source_js.dart`（执行前改写）、新增 `rhino_syntax.dart`（改写）。
- **packages/rule_engine/lib/src/html/css_selector.dart**：文档的基准地址，`abs:` 属性用它。
- **packages/quickjs_ng_ffi/src/quickjs_ng_ffi.c**：预置 JS 加宿主全局（`setGlobals`、`initLib`），jsLib 和变量层的 `this` 上都能用（设计 D6）。
- **测试**：改写的单元测试、Jsoup 和元素方法的 JS 测试；用两份合集统计改写前后的语法错误；模拟器上用书源校验对比「js失效」的数量。
