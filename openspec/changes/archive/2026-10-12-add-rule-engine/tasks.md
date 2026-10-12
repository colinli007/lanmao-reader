## 1. 可中断的正则（quickjs_ng_ffi）

- [x] 1.1 C 胶水新增 `qjs_regexp_compile` / `qjs_regexp_exec` / `qjs_regexp_free`（D5）：用引擎的 `JSContext` 分配内存和检查中断，中止标志的设置与清除方式和 `qjs_eval` 一致；更新头文件并用 ffigen 重新生成绑定。验证：`flutter build macos` 编译通过，生成的绑定里有这三个函数。
- [x] 1.2 Dart 封装 `JsRegExp`：编译（标志和错误原因）、`firstMatch`、`allMatches`（输入只复制一次）、分组范围，接受 `abortSignal`。验证：`js_engine_test.dart` 新增 js-engine 规格里的 4 个场景并通过，包括另一个线程设置中止信号后匹配以错误结束、之后同一正则仍可用。

## 2. rule_engine 包骨架与基础组件

- [x] 2.1 新建 `packages/rule_engine`（pubspec、analysis_options、README 骨架），依赖 `blocking_bridge`、`quickjs_ng_ffi`、`html`；定义 `RuleEnvironment`、`HttpRequest`、`HttpResult` 和错误类型（`NeedsJsException`、`NeedsWebViewException`、`RuleException`）。验证：`dart analyze` 无问题，`dart test` 能跑通一个空测试。
- [x] 2.2 GBK 编解码（D8）：生成脚本读取 WHATWG `index-gb18030.txt` 生成常量表，实现解码器和编码器。验证：单测覆盖 `三体` ↔ `C8 FD CC E5`、GB2312 常用字、非法字节替换为 U+FFFD。
- [x] 2.3 公共后缀匹配（D10）：拷入公共后缀列表（ICANN 和 PRIVATE 两部分）并写匹配器。验证：单测覆盖 `www.a.com` → `a.com`、`x.com.cn` → `x.com.cn`、通配符和例外规则、IP 地址。
- [x] 2.4 宽松 JSON 解析（D9）：照 Gson 宽松模式，支持单引号、不带引号的键和值、`=` 分隔、注释，数组里多余的逗号按 null 处理（对象末尾的逗号和 Gson 一样报错）。验证：单测覆盖 MD3 书源里常见的 `header` 和 URL 选项写法。
- [x] 2.5 Java 正则转换与替换串展开（D5）：`\h`、占有量词、开头的内联标志；`$n`、`${name}`、`\` 转义；编译失败时退化为字面量。验证：单测覆盖这些写法，以及从书源数据里摘出的 10 条真实净化规则。

## 3. 书源载入

- [x] 3.1 书源模型与载入：单个或数组、字符串形式的规则组、缺失字段、跳过无效条目并报告原因、导出时保留未知字段。验证：book-source 规格的全部场景作为单测通过；载入 aoaostar 全量书源文件不抛错，跳过数与 `source-check` 的统计一致。

## 4. HTML 与 jsoup 语义（D6）

- [x] 4.1 jsoup 兼容的文本函数：`text`、`ownText`、`textNodes`、`outerHtml`（含块级元素间补空格、空白规范化）。验证：对照 jsoup 1.16.2 行为的单测，至少 20 个用例。
- [x] 4.2 CSS 选择器解析器与匹配器，覆盖 D6 列出的语法和伪类，选择结果包含当前元素；`:matches` 走 `JsRegExp`。验证：单测覆盖每个伪类、组合符和属性运算符；不支持的伪类以规则错误结束。

## 5. 规则解析与取值（rule-syntax）

- [x] 5.1 规则切分：JS 段切分、取值语法判定（含 JSON 内容上的无前缀规则）、组合运算符切分（括号和引号保护、两种平衡模式）。验证：rule-syntax 规格「识别取值语法」「组合运算符」的场景通过，括号不配对时以规则错误结束。
- [x] 5.2 模板与变量：`##` 切分（含 `###`）、`@put` / `@get`、`{{内嵌规则}}`、`{{baseUrl}}` / `{{title}}`、`$n` 分组引用；其余 `{{}}` 和 `@js:`、`<js>`、`@webjs:` 走 D13 的接入点。验证：「正则净化」「变量与内嵌规则」「需要 JS 时明确报错」三条要求的场景通过。
- [x] 5.3 JSoup 默认语法：各选择器、旧式索引与 `[]` 索引、各取值方式、属性去重、`html` 去掉脚本和样式。验证：「JSoup 默认语法」「文本取值与 jsoup 一致」「CSS 选择器」的场景通过，另按 `research/md3-rule-syntax.md` 第 4 节补充边界用例。
- [x] 5.4 JSONPath（D6a）：Jayway 子集（确定路径返回单值、裸路径补 `$.`），值转字符串与 MD3 一致，`{$.x}` 内嵌，路径不存在时返回空。验证：「JSONPath」要求的场景通过；以 json-path 3.0.0 生成期望值的对照用例全部通过，含 null 值、嵌套对象。
- [x] 5.5 XPath：照 JsoupXpath 移植（D7）。验证：「XPath」要求的场景通过；书源数据里摘出的 126 条（64 条不重复）A 类 XPath 和 JsoupXpath 生成的期望值逐条一致，并在测试里列出报错的条数。
- [x] 5.6 AllInOne 正则与地址取值：`:` 开头的列表规则、粘性的正则模式、相对地址转绝对地址（不做百分号编码）、取地址列表时去空去重。验证：「AllInOne 正则」「地址取值」的场景通过。
- [x] 5.7 取值入口 `getString` / `getStringList` / `getElements` 串起以上部分，空值和 null 的处理与 MD3 一致。验证：「书源正则可以被中止」场景通过（在 worker 池里运行，取消后 worker 没有被放弃）。

## 6. 请求构造与网络（source-request）

- [x] 6.1 worker 端请求构造：URL 模板、页码列表、URL 选项（宽松 JSON、各字段、`js` / `webView` 报错）、查询串编码（UTF-8、GBK、escape）、POST 请求体、请求头合成。验证：「URL 模板」「URL 选项」「请求参数编码」「请求头」要求的场景作为单测通过，不连网。
- [x] 6.2 响应解码：BOM、Content-Type、meta、UTF-8 或 GBK 回退，以及无法识别的编码名。验证：「响应解码」要求的场景通过。
- [x] 6.3 主 isolate 端 `RuleHost`：`HttpClient` 手动跟随重定向、接受无效证书、超时、取消时中断请求、批量并发、回复帧格式（D2）。验证：用本地 HTTP 服务测试「网络请求在主 isolate 上执行」和「响应处理」的场景。
- [x] 6.4 `CookieStore` 与限速器（D4）。验证：「跨 worker 共享 Cookie」「书源限速」的场景用两个 worker 加本地服务测试通过。

## 7. 四条链路（book-chains）

- [x] 7.1 链路数据模型（`SearchBook`、`Book`、`BookChapter`，带变量）和四个顶层任务工厂；链路在每次请求前、每页处理后检查取消。验证：「链路在 worker 中执行」的场景通过。
- [x] 7.2 搜索与「搜索结果直接是详情页」。验证：对应两条要求的场景通过，直接命中详情页时，详情链路的请求数为 0。
- [x] 7.3 详情。验证：「详情」要求的场景通过，目录就在详情页时，目录链路的请求数为 0。
- [x] 7.4 目录与多页目录。验证：「目录」「多页目录」要求的场景通过。
- [x] 7.5 正文与多页正文（格式化、图片地址、`replaceRegex`、遇到下一章停止）。验证：「正文」「多页正文」要求的场景通过。

## 8. 真实书源验证

- [x] 8.1 录制与冒烟工具 `tool/smoke.dart`：对指定书源和搜索词跑完整链路，输出各链路成功数和失败原因；加 `--record` 时保存全部响应作为固定样例。验证：对 1 个书源跑通并生成样例文件。
- [x] 8.2 录制 8 个真实书源的固定样例（覆盖 D14 列出的情形），对照网页人工核对关键字段后写成测试。验证：`dart test` 在不联网的情况下通过这 8 组样例测试。（「搜索直达详情页」这次没有找到能复现的站点，只有单元测试覆盖，其余情形都有录制样例。）
- [x] 8.3 对精品子集里的 A 类书源跑一次冒烟，把各链路成功数、失败原因分布、编译失败的正则数写进选型文档。验证：文档里有这组数据和运行日期。
- [x] 8.4 spike 新增一项验证：在 worker 池里对一个真实书源跑完整的四条链路；在 Android 真机上用 `flutter drive --profile` 运行。验证：真机上全部验证项通过。

## 9. 文档

- [x] 9.1 `packages/rule_engine/README.md`（用法、两端接入方式、测试命令、与 MD3 的偏离表），更新根目录 README 的目录表和测试命令。验证：按 README 的命令能跑通测试。
- [x] 9.2 选型文档：网络层改为 `dart:io` 并说明原因（D3）；XPath 和 GBK 的实际选择；更新「下一步」第 3 条的进度和剩下的前置问题。验证：文档与实现一致。
