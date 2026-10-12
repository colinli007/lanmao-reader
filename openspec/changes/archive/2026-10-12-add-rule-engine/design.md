## Context

动机和范围见 proposal.md，行为要求见 specs/。MD3 的语义清单整理在 `research/` 目录下，实现时逐条对照：
- `research/md3-rule-syntax.md`：规则拆分、各取值语法、组合运算、净化、变量；
- `research/md3-request-and-chains.md`：URL 模板、请求选项、编码、Cookie、限速、四条链路。

现状和约束：

- **阻塞桥**（`packages/blocking_bridge`）：任务是 worker 里同步执行的 Dart 闭包，用 `WorkerContext.current.callHost(op, payload)` 同步等待主 isolate；宿主可以返回 JSON 值或原始字节；任务有截止时间和取消；`abortSignal` 是共享内存里的中止标志。
- **JS 引擎**（`packages/quickjs_ng_ffi`）：每个 worker 一个 `JsEngine`，它的 C 胶水已经有中止标志的检查。quickjs-ng 自带的 libregexp 在回溯时调用 `lre_check_timeout(ctx)`，这个函数最终会走到引擎的中断回调。
- **环境**：本机 Flutter 3.32.4 / Dart 3.8.1。pub 上能找到的 GBK 编码库、公共后缀库、XPath 库，要么只支持 Dart 2，要么要求 Dart 3.11（见 D7、D8、D10）。`package:html` 能解析 HTML，但它的 CSS 选择器不支持 jsoup 的伪类。
- **书源数据**（aoaostar/legado，A 类 1515 条）：
  - 取值语法：JSoup 默认语法 70%，`##` 净化 59%，JSONPath 5%，XPath 2.6%，CSS 1.3%，AllInOne 正则 1 条；
  - 请求相关：Cookie 51%，POST 22%，下一页正文 24%，多页目录 18%，GBK 14%；
  - CSS 里用到 jsoup 伪类的约 40 条：`:nth-of-type`、`:has`、`:not`、`:contains`、`:matches`；
  - `{{}}` 里除了内嵌规则，只出现过 `key`、`page`、`baseUrl`、`title`；
  - 3597 个正则里，只有十几个用了 Java 专有写法（`\h`、占有量词）。

## Goals / Non-Goals

**Goals:**
- A 类书源在本引擎上的解析结果与 MD3 一致，包括 MD3 的怪异行为，例如对象形式的 body 带缩进发送、`###` 的切分方式。书源作者是对着 Legado 调的规则，对齐才是兼容。
- 引擎核心是同步代码，网络和取消检查都从外部注入，这样不起 isolate 也能做单元测试和固定样例测试。
- 给 JS 运行时的 change 留好接入点，并保证需要 JS 的地方一个都不漏掉、不会静默跳过。

**Non-Goals:**
- 不复刻 MD3 的崩溃。MD3 会抛 NPE、AssertionError 或越界的地方，这里返回明确的错误。偏离点见 D12。
- 不做 HTTP 缓存。MD3 有 100MB 的 OkHttp 缓存，那是性能优化，不影响解析结果。
- 不做代理（`header` 里的 `proxy` 键）和 `dnsIp`、`serverID` 这类选项，遇到时忽略。
- Cookie 和变量只存在内存里，持久化等存储层出来再做。

## Decisions

### D1 包结构：同步的引擎核心 + 两端适配

新增 `packages/rule_engine`，分三层：

- **核心层**（同步，不感知 isolate）：书源模型、规则解析和取值、请求构造、响应解码、四条链路。网络和取消都从外部注入：
  ```dart
  abstract interface class RuleEnvironment {
    HttpResult fetch(HttpRequest request);                  // 同步取一个请求
    List<HttpResult> fetchAll(List<HttpRequest> requests);  // 同步取一批，主侧并发
    void checkCancelled();                                  // 被取消时抛错
    Pointer<Int32> get abortSignal;                         // 交给正则引擎
  }
  ```
- **worker 端**：用 `WorkerContext.current` 实现 `RuleEnvironment`；每条链路对应一个顶层任务工厂（`searchTask(source, key, page)` 等），交给 `WorkerPool.run`。工厂必须是顶层函数，原因见 blocking_bridge 的 README。
- **主 isolate 端**：`RuleHost` 处理 `http`、`httpBatch` 两种宿主请求，持有 HTTP 客户端、Cookie 存储和限速器（D3、D4）。

测试时，核心层使用一个读取录制样例的 `RuleEnvironment`，不用起 isolate，也不连网。

**备选**：链路直接写在任务闭包里，直接调用 `callHost`。这样每个测试都要起 worker 池和本地服务器，规则语义的测试会又慢又难定位。

### D2 网络在主 isolate，worker 只收字节

worker 发出的请求是 JSON：地址、方法、请求头、请求体（字符串，已经按 D9 编码好）、书源地址（用于 Cookie 分组和限速）、是否开启 CookieJar。主 isolate 回复字节，格式是「4 字节元数据长度 + 元数据 JSON + 响应体」，元数据里有状态码、最终地址和响应头。批量请求的回复把多个这样的帧依次拼在一起。解码放在 worker 里，因为编码判定要看 meta 标签，属于解析的一部分。

**为什么不在主 isolate 解码**：主 isolate 要保持流畅，几百 KB 的 GBK 页面解码不应该放在 UI 线程上。

**为什么回复用字节、不用 JSON**：响应体是任意字节，转成 JSON 字符串既要先解码，又会膨胀体积。阻塞桥本来就支持原样传字节。

### D3 HTTP 用 `dart:io` 的 `HttpClient`，自己处理重定向

关闭 `followRedirects`，在主 isolate 上手动跟随重定向（最多 20 跳）：
- 每一跳都按 D4 合并 Cookie，最终地址取最后一跳的请求地址；
- `badCertificateCallback` 一律返回 true，与 MD3 一致；
- 连接超时 15 秒，单次请求总超时 60 秒；
- 宿主请求的 `cancelled` 完成时，强制关闭这个请求。

**和选型文档的偏离**：文档原定用 `dio` 加 `cookie_jar`。但 MD3 的 Cookie 模型（D4）和 `cookie_jar` 实现的 RFC 6265 模型不同：MD3 按注册域名分组、只存名和值、每次请求都带上书源域名的 Cookie。逐跳合并 Cookie 又要求手动处理重定向。这样 dio 只剩一层包装，没有实际用处。实现完成后同步更新选型文档。

### D4 Cookie 照 MD3 的模型，按注册域名分组

`CookieStore` 放在主 isolate 上，是一个以注册域名为键、值为 `name → value` 映射的表。行为照 `research/md3-request-and-chains.md` 第 2 节：
- 每个请求都带上书源域名的 Cookie，请求头里已有的值优先；
- 开启 CookieJar 时，每一跳再合并实际请求域名的 Cookie，这次已保存的值优先，并保存响应的 `Set-Cookie`；
- 值为空白的 Cookie 丢弃；
- 不区分持久 Cookie 和会话 Cookie，因为这次只做内存存储。

注册域名用公共后缀列表计算（D10）。所有 worker 的请求都经过主 isolate，所以 Cookie 天然只有一份。这就是规则引擎这一侧对「跨 worker 状态」这个前置问题的答案。`@put` / `@get` 变量跟着书籍和章节对象走，属于任务数据，不需要跨 worker 共享（D11）。

### D5 书源正则走 libregexp，响应中止标志

`quickjs_ng_ffi` 新增正则接口，直接调用 libregexp：
- C 胶水提供 `qjs_regexp_compile(engine, pattern, flags, ...)`、`qjs_regexp_exec(engine, bytecode, utf16, len, start, abort_flag, captures)` 和 `qjs_regexp_free`；
- 分配内存和中断检查都用这个引擎的 `JSContext`，因为 libregexp 会把它作为 `opaque` 传给 `lre_realloc` 和 `lre_check_timeout`；
- 中止标志的设置方式和 `qjs_eval` 相同：调用期间设到引擎上，嵌套在求值里时沿用外层的标志，退出最外层时清除。

Dart 侧封装为 `JsRegExp`，提供 `firstMatch`、`allMatches` 和替换。一次替换只把输入复制成 UTF-16 一次，然后在同一块内存上循环查找。每个 worker 把编译好的正则存进 LRU 缓存，上限 256 条，因为同一个书源的净化规则会反复使用。

**Java 和 JS 正则的差异**：编译前做一次轻量转换：`\h` 换成等价的字符类；占有量词（`*+`、`++`、`?+`）降为普通贪婪量词；开头的 `(?s)`、`(?i)`、`(?m)` 转成标志。默认不开 Unicode 标志，按 Annex B 的宽松语法编译，这样能兼容 Java 允许、JS 严格模式却会报错的转义写法。替换串按 Java 语法（`$n`、`${name}`、`\` 转义）在 Dart 里展开。编译失败时，按 MD3 的做法退化为字面量替换。

**Android 上的 Java 正则是 ICU。** MD3 跑在 Android 上，`java.util.regex` 底层是 ICU，和桌面 JVM 不同：`\d` 是全部 Unicode 十进制数字（含全角数字），`\w` 含汉字，`\s` 含全角空格。JS 的 `\s` 和 ICU 基本一致，`\d`、`\w` 只认 ASCII，所以转换时把 `\d`、`\w`（以及字符类外的 `\D`、`\W`）换成等价的 Unicode 字符类（限 BMP，第一次用到时扫描生成）。引擎自己写死的正则（格式化正文、清洗书名）直接用 Dart 的 `\s`，效果和 MD3 一致：例如格式化正文时 `^[\n\s]+` 会连带去掉已有的全角缩进，段首只缩进一次。

**只有书源提供的正则走这里。** 引擎自己写死的正则（清洗书名、格式化正文）用 Dart `RegExp`，这些正则是我们自己写的，没有灾难性回溯的风险。

**备选 1**：用 Dart `RegExp`，卡住了就放弃 worker。被放弃的 worker 会一直占着线程和 CPU，书源里一条写坏的净化规则就可能拖垮整个池。
**备选 2**：把正则放到 JS 里执行（`str.replace(new RegExp(...))`）。中止路径可以直接复用，但每次都要把 1MB 的正文转成 JS 字符串再转回来，还要绕过 JS 的执行环境；而且 B、C 类书源以后要的作用域隔离也会牵扯进来。

### D6 HTML：`package:html` 负责解析，jsoup 语义自己实现

`package:html`（html5lib 的移植）负责把 HTML 解析成 DOM。下面几项要按 jsoup 1.16 的行为自己实现：

- **文本**：`text()`、`ownText()`、`textNodes`、`outerHtml()` 的空白规范化，以及块级元素之间补空格。按 jsoup 源码移植，用对照用例锁定行为。
- **CSS 选择器**：自己写解析器和匹配器，语法照 jsoup 的 `QueryParser`：
  - 标签、`#id`、`.class`、属性选择（`=`、`^=`、`$=`、`*=`、`~=` 正则、`[^前缀]`）；
  - 组合符（空格、`>`、`+`、`~`）和逗号；
  - 伪类：`:lt`、`:gt`、`:eq`、`:has`、`:not`、`:contains`、`:containsOwn`、`:matches`、`:matchesOwn`、`:nth-child`、`:nth-last-child`、`:nth-of-type`、`:nth-last-of-type`、`:first-child`、`:last-child`、`:first-of-type`、`:last-of-type`、`:only-child`、`:only-of-type`、`:empty`、`:root`。
  - `:matches` 里的正则走 D5。不支持的伪类以规则错误结束。
- **选择范围包含当前元素本身**，与 jsoup 的 `select`、`getElementsBy*` 一致。

**备选**：用 `package:html` 自带的 `querySelectorAll`。它不支持上面列出的大部分伪类，也不包含当前元素本身，约 40 条 A 类书源会直接失败。

### D6a JSONPath：自己实现 Jayway 子集

MD3 用 Jayway json-path 3.0.0（json-smart 2.6.0），它和 `json_path` 包遵循的 RFC 9535 有几处根本差别：
- 不以 `$` 开头的路径自动补 `$.`（JSON 书源里大量规则是 `name`、`data.list` 这样的裸路径）；
- 属性名可以含 `-` 等字符，到 `.`、`[`、`(` 为止；
- 确定路径返回单个值、取不到时报错，不确定路径返回列表；
- 值转字符串时，对象是 Java `Map.toString`（`{k=v}`），数组是 json-smart 的紧凑 JSON，小数是 Java `Double.toString`。

书源里实际用到的写法只有 `.name`、`..`、`[*]`、`[n]`（含负数）和一个 `[?()]` 过滤，所以直接写一个 Jayway 子集（属性、下标、切片、通配、深度扫描、过滤），不再依赖 `json_path`。行为用 `tool/jsoup_oracle/` 里的对照工具，以真实的 json-path 3.0.0 生成期望值来锁定。

### D7 XPath：照 JsoupXpath 移植

MD3 用 JsoupXpath 2.5.5，它是基于 ANTLR 的一套 XPath 方言，和标准 XPath 1.0 有不少差别：`text()` 生成文本伪元素、`[n]` 按上下文中同名的兄弟计序号、`position()` 返回整数而数字字面量是小数（`position()=1` 永远不成立）、`//` 之后的名字测试用 CSS 选择且包含上下文元素本身、`text`/`html`/`node` 是关键字不能当元素名、语法规则不要求到结尾（多余的内容被忽略）。书源作者是对着这些行为写的规则，所以照它的 `XpathProcessor` 逐条移植（词法、递归下降语法分析、作用域栈、节点测试、轴和函数），作用在 D6 的同一份 DOM 上。

行为用 `tool/jsoup_oracle/` 里的对照工具以真实的 JsoupXpath 生成期望值来锁定，书源里 64 条不重复的 A 类 XPath 全部在对照用例里。只有一处无法对齐：JsoupXpath 在 `..` 和 `descendant` 轴上用 HashSet 去重，结果顺序取决于对象哈希，本身不确定，这里按文档顺序输出。

**备选**：把 `xpath_selector` 拷进仓库，或者按 XPath 1.0 自己实现。前者要求 Dart 版本低于 3.0；两者的语义都和 JsoupXpath 对不上。

### D8 GBK 编解码表从 WHATWG 编码标准生成

从 WHATWG Encoding Standard 的 `index-gb18030.txt` 生成一个 Dart 常量表（双字节部分，约 2.4 万项），写一个 GBK 解码器（兼容 GB2312）和编码器（用于搜索词）。生成脚本和来源版本一起提交，表只生成一次。

**备选**：`enough_convert`（要求 Dart 3.11）、`fast_gbk` 和 `gbk_codec`（只支持 Dart 2）、`charset`（2023 年后不再更新，单人维护）。升级 Flutter 是另一件事，不应该绑在这个 change 里。

### D9 请求参数编码在 worker 里完成

URL 模板、页码、选项解析、查询串编码、表单编码、请求头合成，都在 worker 的核心层完成。主 isolate 只收到最终的地址、请求头和请求体，不需要理解书源。宽松 JSON（单引号、不带引号的键）自己写一个小解析器，只用于 `header` 和 URL 选项。

### D10 公共后缀列表拷进仓库

把 publicsuffix.org 的列表（MPL-2.0）拷进 `rule_engine`，写一个约百行的匹配器（支持普通规则、通配符和例外规则），用来计算注册域名。IP 地址按原样返回。列表包含 ICANN 和 PRIVATE 两部分，和 MD3 用的 OkHttp `PublicSuffixDatabase` 一致；只拷 ICANN 部分的话，`foo.github.io` 这类主机的分组会和 MD3 不同。

### D11 链路数据和变量

书籍（`Book`）、搜索结果（`SearchBook`）和章节（`BookChapter`）都是普通的 Dart 类，可以直接在 isolate 之间传递，各自带一个 `variables` 映射。
- `@put` 写入当前链路的书籍或章节；`@get` 按章节、书籍、本次链路的顺序读取，和 MD3 一致。
- 搜索直接命中详情页时，页面保存在 `Book.infoHtml`；目录就在详情页时，页面保存在 `Book.tocHtml`，下一条链路直接使用（对应 spec 里「不再请求一次」）。

### D12 与 MD3 的偏离（都只发生在 MD3 自己会出错的地方）

| MD3 的行为 | 本引擎 |
|---|---|
| `init` 用正则或 JSONPath 取不到时 `setContent(null)` 抛 AssertionError（JSoup、XPath 取不到时是空列表，不报错） | 以「详情 init 取不到」错误结束 |
| `@css:` 取字符串的规则里没有 `@` 时越界崩溃 | 以规则错误结束 |
| `http-equiv` 的 content 里没有 `charset=` 时，把整段当编码名，抛错 | 按没有声明处理 |
| 无法判定编码时用 ICU 自动检测 | 合法 UTF-8 就按 UTF-8 解码，否则按 GBK 解码（中文书源的实际情况） |
| 区间索引在 len=0 时越界 | 结果为空 |
| 多页并发时 body 为空抛 NPE | 这一页按空内容处理 |
| 页码 `page=0` 越界 | 按第 1 页处理 |

### D13 JS 接入点：先抛错，不建接口

规则引擎里每个需要 JS 的位置（`@js:` 段、`<js>`、`{{表达式}}`、URL 里的 `js`、`bodyJs`、JS 形式的 `header`），都调用同一个内部函数 `_requireJs(位置, 片段)`，抛出 `NeedsJsException`。WebView 相关的位置调用 `_requireWebView`。下一个 change 把这两个函数换成真正的调用。

现在不提前抽象 `ScriptHost` 接口，因为 JS 运行时要什么上下文（绑定哪些对象、作用域怎么隔离）要等那个 change 来定。

### D14 测试策略

- **语义单元测试**：每条 spec 场景至少一个测试，再按 `research/` 里的清单补边界用例。用例写成「规则 + 内容 → 期望结果」的表，测试里注明对应 MD3 源码的位置。
- **固定样例测试**：从真实 A 类书源里挑 8 个，覆盖 JSoup 默认语法、CSS、JSONPath 接口、XPath、GBK 站点、POST 搜索、多页目录、多页正文。搜索直达详情原计划也要录，但 2026-10-12 冒烟时设置了 `bookUrlPattern` 的书源都返回列表，没有能复现的站点，这个情形只有单元测试覆盖。用录制工具保存四条链路的全部响应（地址、最终地址、响应头、字节），用 D1 的回放环境运行。期望值是录制时对照网页人工核对过的关键字段：书名、作者、章节数、首尾章节名、正文开头。
- **联网冒烟**：`tool/smoke.dart` 对一批 A 类书源跑完整链路，报告各链路的成功数和失败原因分布，结果写进文档，不设门槛。和 MD3 的批量差分在单独的 change 里做。
- **端到端**：spike 增加一项验证：在 worker 池里对一个真实书源跑完整的四条链路，在 Android 真机上用 AOT 构建运行。
- **运行方式**：所有测试都需要本机编译的 quickjs 动态库（正则要用），方式和 `quickjs_ng_ffi` 的测试相同（设置 `QUICKJS_NG_FFI_LIB` 环境变量）。

## Risks / Trade-offs

- **[jsoup 的文本和选择器语义难以完全对齐]** → 按 jsoup 1.16.2 源码移植，用对照用例锁定；差分测试那个 change 会用大量书源批量发现剩下的差异。
- **[Java 正则和 JS 正则的差异]**：实测只有十几个正则用到 Java 专有写法，转换层覆盖了这些写法 → 转换覆盖不到的写法会编译失败，按 MD3 的规则退化为字面量替换，结果可能和 MD3 不同；冒烟工具会统计编译失败的正则。
- **[接受无效证书有中间人风险]** → 与 MD3 行为一致，书源站点大量使用自签或过期证书。只影响书源请求，app 自己的服务不走这个客户端。
- **[编码判定简化]**：用「UTF-8 或 GBK」代替 ICU 检测，Big5 等编码会解错 → A 类书源声明的 charset 只出现过 gbk、gb2312、utf-8；以后遇到其它编码再补。
- **[自己写的组件多]**：CSS 选择器、XPath、GBK、公共后缀、宽松 JSON 都是自己写的，代码量比直接用库大 → 每一项都有明确的规范或参照源码，测试可以逐条对照；比起绑定一个停更、语义还不一致的库，长期维护成本更低。
- **[正则在 worker 的 JS 引擎上执行]**：正则编译出来的内存来自这个引擎的分配器 → 缓存的正则和引擎生命周期相同，worker 退出时一起释放；正则对象不跨 isolate 传递。

## Migration Plan

新增包，不改动现有接口。`quickjs_ng_ffi` 只新增函数。spike 新增一项验证。没有需要回滚的数据。

## Open Questions

- **冒烟工具挑哪些书源、用什么搜索词**：实现时从精品子集里挑，搜索词用几本热门书名。只影响冒烟报告，不影响实现。
- **LRU 缓存上限 256**：按冒烟中每个 worker 的正则数量再调，只影响默认值。
