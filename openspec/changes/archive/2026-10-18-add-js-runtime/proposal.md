## Why

规则引擎目前只能跑没有 JS 的 A 类书源，遇到 `@js:`、`<js>`、`{{表达式}}` 就以「需要 JS 引擎」结束。按 source-check 对全量 3310 个书源的分级，A 类 1515 个（46%）；有 JS 但不调用宿主 API 的 B 类 859 个，调用宿主 API 的 C 类 538 个，合计 42%。阻塞桥、可中止的 quickjs-ng、主 isolate 上的网络和 Cookie 都已就位，现在补上 JS 运行时，引擎能力覆盖的书源可以从不到一半提高到八成以上（这是能力上的覆盖，书源对应的网站是否还有效另说）。

## What Changes

- 新增书源 JS 运行时：规则里的 `<js>`、`@js:`、`{{表达式}}`，URL 里的 `@js:`、`<js>`、`{{表达式}}` 和 `js`、`bodyJs` 选项，书源 `header` 的 JS，`jsLib`，`loginCheckJs`，目录的 `formatJs`，都按 MD3（legado-with-MD3 `d1b488b`）的语义执行。
- 每次求值使用独立的作用域：注入 `java`、`result`、`baseUrl`、`book`、`chapter`、`source`、`cookie`、`cache` 等变量，顶层声明不泄漏到下一次求值；`jsLib` 作为共享的一层，按书源 JS 的写法可见。
- 实现高频宿主 API（不依赖界面和 WebView 的部分）：网络（`ajax`、`ajaxAll`、`connect`、`get`、`post`、`head`）、变量（`java.put/get`、`source/book/chapter` 的变量）、回调规则（`getString`、`getStringList`、`getElement(s)`、`setContent`）、编码、摘要与加解密、时间、日志、Cookie、缓存、书源与登录头。`java` 在规则、URL、书源三种上下文里是三个不同的对象，各自的语义照 MD3。
- `getElement(s)` 和 `result` 是 HTML 元素时，JS 拿到带 jsoup 常用方法（`text`、`attr`、`select`、`html`、`toArray` 等）的包装对象；网络 API 返回带 `body()`、`headers()`、`code()` 等方法的响应对象。
- 界面类 API（`toast` 除外）、WebView 类 API、文件、字体、设备标识、简繁转换等不在本次范围，调用时以「不支持的宿主 API」错误结束并带上 API 名；`toast` 降级为日志。
- **BREAKING**（对 rule_engine 的调用方）：上面这些位置不再抛 `NeedsJsException`；该异常改为只表示用到了不支持的 JS 能力。
- quickjs-ng 绑定增加「隔离作用域求值」接口。
- 跨 worker 共享的书源级状态（`cache.*`、书源变量、登录头）放到主 isolate 上，和 Cookie 一样只有一份；本次用内存实现，持久化留给 app 外壳。

## Capabilities

### New Capabilities
- `source-js`: 书源 JS 的执行模型：各个 JS 进入点、求值前的文本预处理、作用域与 `jsLib`、注入变量、JS 与规则引擎之间的值转换、错误与取消。
- `source-js-api`: 注入书源 JS 的宿主 API（`java`、`cookie`、`cache`、`source`、`book`、`chapter`）的语义，包括按上下文区分的 `java` 对象、元素和响应的包装对象，以及不支持的 API 怎样报错。

### Modified Capabilities
- `js-engine`: 增加隔离作用域求值：每次求值用新的变量层，返回最后一个表达式的值，顶层声明和未声明赋值不泄漏，可以挂一层共享作用域。
- `rule-syntax`: 规则里的 `@js:`、`<js>`、`{{表达式}}` 从报错改为执行；`{{x}}` 的判定补上 JS 分支。
- `source-request`: URL 模板里的表达式和 JS、`js` 与 `bodyJs` 选项、书源 `header` 的 JS 从报错改为执行；新增 `loginCheckJs`。
- `book-chains`: 链路错误的说明从「需要 JS」改为「不支持的宿主 API」；目录增加 `formatJs`。

## Impact

- 代码：`packages/quickjs_ng_ffi`（C 胶水和 Dart 接口）；`packages/rule_engine` 新增 `js/` 目录（运行时、宿主 API、包装对象、加解密），改动 `rule/analyze_rule.dart`、`request/analyze_url.dart`、`chain/chains.dart`、`host/rule_host.dart`、`core/environment.dart`、`worker/`。
- 依赖：新增纯 Dart 的加解密库（AES、DES、DESede、MD5、SHA、HMAC），具体选型见 design。
- 测试：加解密、编码、时间格式的期望值由 `tool/jsoup_oracle` 用 JDK 和 Hutool 生成；B、C 类真实书源联网冒烟并录制样例。
- 文档：选型文档的规则引擎进度和冒烟结果。
- 不涉及 app 外壳；持久化存储、界面交互、WebView 在后续 change 处理。
