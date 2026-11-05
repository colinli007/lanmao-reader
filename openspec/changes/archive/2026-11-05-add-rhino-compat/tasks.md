## 1. 实现

- [x] 1.1 `rhino_syntax.dart`：解构箭头函数的改写（D4），接到 `SourceJs._run` 和 jsLib。验证：单元测试覆盖改写、字符串、模板、注释、正则、下标访问、已有括号。

  结果（2026-11-05）：`rhino_syntax_test.dart` 6 个，`source_js_test.dart` 加规则和 jsLib 里的两个。
- [x] 1.2 `org`、`Packages` 包对象和 Jsoup（D1、D3）；元素的 `data`、`remove`，列表的 `remove`；文档的基准地址（D2）。验证：JS 测试覆盖 source-js-api「Jsoup」「元素包装对象」和 source-js「使用 Packages」。

  结果（2026-11-05）：跑合集时发现 jsLib 在自己的 JSContext 里执行，看不到 `org`、`Packages`（Rhino 的 jsLib 作用域是顶层作用域，有 `Packages`；书源还会写 `const { java, Packages } = this`）。所以在 quickjs_ng_ffi 的预置 JS 里加了「宿主全局」`__qjs.setGlobals`：定义在全局对象和变量层的原型上，jsLib 执行前复制到 jsLib 的全局对象上；规则引擎用它注册 `org`、`Packages`。同时发现 jsLib 第一次执行时还没有当前求值帧，顶层调用宿主会漏出 Dart 的 `Bad state` 错误，改成先压入帧再执行 jsLib。测试：Jsoup 4 个、jsLib 里用 Java 包 2 个、`Packages` 和 `new org.*` 1 个，quickjs_ng_ffi 加宿主全局 1 个。
- [x] 1.3 `getWebViewUA`（D5）。验证：JS 测试。

## 2. 验证和文档

- [x] 2.1 引擎和 app 全量测试、analyze。

  结果（2026-11-05）：引擎 935 个、quickjs_ng_ffi 41 个、app 376 个通过，analyze 无问题。
- [x] 2.2 两份合集：发现分类重新解析一遍，统计失败原因的变化；Android 模拟器上用合集 1329 校验书源，对比「js失效」的数量（上次 42 个）。

  结果（2026-11-05）：
  - 发现分类（不连网，只算文本书源）：合集 1329 成功从 157 个到 177 个（共 181 个）；794 个的合集从 455 个到 485 个（共 505 个）。剩下的主要是测试环境不连网、`t2s`、`JavaImporter`、`infoMap`。
  - 模拟器（API 36，debug 包）上用「我的」校验 321 个书源：通过 132（上次 130），js失效 28（上次 42），网站失效 121（上次 111，网站本身的变化），搜索失效 36，搜索目录失效 2，搜索正文失效 2。剩下的 js失效：jsLib 的 JSON 形式 5、`cannot read property '1' of null` 5、`java.webView` 3、`t2s` 2、`JavaImporter` 2、`Packages.io.legado…StrResponse` 2，其余各 1 个。
  - 发现页走查时出错的《黄金屋》「玄幻小说」（列表规则用 `org.jsoup.Jsoup.parse`）现在能列出书。
- [x] 2.3 PRD、README、发布说明的已知限制同步。
- [x] 2.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。
