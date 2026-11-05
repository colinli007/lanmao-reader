## Context

- 元素交给 JS 时是句柄：Dart 的 `Node` 登记到 `HandleTable`，JS 侧是 `JsElement`（`prelude.dart`），方法经 `__host.call('el.xxx')` 回到 Dart，用 `jsoupText`、`jsoupAttr`、`CssSelector` 等 jsoup 兼容实现。元素列表是带隐藏方法的数组。
- 不支持的宿主 API：JS 调用时 `hostCall('unsupported', [名字])`，Dart 抛 `UnsupportedHostApiException`，JS 的 try/catch 拦不住。
- 书源 JS 都经过 `SourceJs._run`（规则、URL、书源级、图片解密）和 `_lib`（jsLib）执行；目录的 `formatJs` 走 `formatChapterTitles`。
- 现在的规格（source-js「Rhino 专有写法」）要求 `Packages.*` 等写法以 JS 错误结束，不静默改写语义。

书源里 `Jsoup.parse` 之后用到的方法（两份合集）：`select`、`get`、`size`、`attr`、`text`、`first`、`html`、`toArray` 都已经有；缺的是 `remove`（9 个书源）、`ownText`（已有）、`data`（2 个）、`getAllElements`、`parents`（各 1 个）。

## Goals / Non-Goals

**Goals：** 用 `Jsoup.parse`、解构箭头函数、`getWebViewUA` 的书源能执行；其余 Java 类的错误说清楚是哪个类。

**Non-Goals：** 模拟其它 Java 类（`String`、`ArrayList`、`Cipher` 等）；jsLib 的 JSON 形式；`Jsoup.connect`。

## Decisions

### D1 Jsoup 用现有的 jsoup 兼容实现

`org.jsoup.Jsoup.parse(html)` 在 Dart 侧用 `package:html` 解析成文档（和 jsoup 规则解析页面相同），作为元素句柄交回 JS。文档上的 `select`、`text` 等直接用现有的 `el.*` 实现，结果和 `@css:`、jsoup 规则一致。

`parseBodyFragment` 也按整页解析：`package:html` 解析片段时同样补上 `html`、`body`，内容在 `body` 里，和 jsoup 相同。

### D2 基准地址

jsoup 的 `attr('abs:href')` 按文档的基准地址把相对地址转成绝对地址；没有基准地址时只有本来就是绝对地址的能取到（现在的行为）。`Jsoup.parse(html, 基准地址)` 把基准地址记在文档上（`Expando`），`jsoupAttr` 遇到 `abs:` 时找到元素所在的文档，有基准地址就按 Java URL 的规则解析，解析不了时为空串（jsoup 的 `absUrl`）。

规则引擎自己解析的页面不设基准地址，和 MD3 一样（MD3 的 `AnalyzeByJSoup` 用 `Jsoup.parse(text)`）。

### D3 其它 Java 类：不支持的宿主 API

`org` 和 `Packages` 是全局的包对象（`Proxy`）：已知的路径（`org.jsoup.Jsoup.parse` 等）返回实现，其余任何属性都返回下一层包对象，调用或 `new` 时以「不支持的宿主 API：完整类名」结束。

为什么不是 JS 错误：Rhino 里这些写法能正常执行，和其它不支持的宿主 API 一样是能力缺口，书源的 try/catch 不该把它吞掉、继续走一条和 Legado 不同的路。错误消息带完整类名，书源校验和用户都能看出是哪个类。

`java.lang.String` 这类以 `java` 开头的不在此列：`java` 是宿主对象，`java.lang` 是 undefined，照旧是 JS 错误。

### D4 解构箭头函数：执行前改写

Rhino 的 `arrowFunctionParams`：`=>` 前面是数组字面量或对象字面量时，当成解构参数。QuickJS 要求加括号。合集里只出现了数组形式（对象形式 0 个），所以只改写数组形式：

- 先用正则 `\]\s*=>` 检查，没有就原样执行（绝大多数代码走这条路，不扫描）。
- 有的话逐字扫描，跳过字符串、模板字符串（包括 `${}` 里嵌套的代码）、注释和正则字面量。
- 记录每个 `[` 是不是出现在表达式开头（前面是运算符、`(`、`,`、`=`、`:`、`{`、`}`、`;`、开头或 `return` 等关键字，而不是标识符、数字、`)`、`]`——那是下标访问）。
- 和它配对的 `]` 后面（跳过空白）紧跟 `=>` 时，在 `[` 前插 `(`、`]` 后插 `)`。

正则字面量和除号的区分按前一个有意义的记号：标识符（非关键字）、数字、`)`、`]` 之后的 `/` 是除号，其余是正则。

改写放在 `SourceJs._run` 和 jsLib 的入口，书源里所有 JS 都经过这里。

### D6 jsLib 里也能用：宿主全局

jsLib 在自己的 JSContext（realm）里执行，全局对象上只有标准 JS，看不到主 realm 里的 `org`、`Packages`。Rhino 的 jsLib 作用域是顶层作用域，`Packages`、`org` 都在上面；书源在 jsLib 的函数里直接用它们，或者写 `const { java, Packages } = this`（`this` 是调用方的作用域，原型链通到顶层）。

所以在 quickjs_ng_ffi 的预置 JS 里加通用的「宿主全局」`__qjs.setGlobals(对象)`：
- 定义在主 realm 的全局对象上，规则里的 JS 直接能用。
- 也定义在 `hostProto` 上。变量层和 jsLib 的 Proxy 以前以 `Object.prototype` 为底，现在以 `hostProto`（继承 `Object.prototype`）为底，所以变量层的 `this` 上也能读到。
- jsLib 执行之前，`initLib` 把它们复制到 jsLib 的全局对象上（在记录「jsLib 新增的名字」之前，所以不算 jsLib 的名字）。

规则引擎的预置 JS 用它注册 `org`、`Packages`。

jsLib 第一次执行时，顶层代码可能调用宿主（例如 `Packages.xxx`），宿主 API 要有当前求值帧。原来是先执行 jsLib 再压入帧，改成先压入帧；jsLib 里不可捕获的错误原样往外，由 `_run` 统一还原。

### D5 getWebViewUA

MD3 返回 `WebSettings.getDefaultUserAgent`，即系统 WebView 的 UA。我们没有 WebView，返回一个固定的 Android WebView UA（带 `; wv)` 和 `Version/4.0`）。书源用它是为了让请求看起来来自 WebView，固定值能满足。

## Risks / Trade-offs

- 改写只认 `[...]=>`；书源若在正则字面量的判断上和我们不同（例如 `}` 之后的 `/`），极少数情况下会扫描出错，最坏结果是没有改写，和现在一样报语法错误。
- `Proxy` 包对象让 `typeof org.xxx` 变成 `function`，和 Rhino 的 `NativeJavaPackage`（`object`）不同；书源很少这样判断。
