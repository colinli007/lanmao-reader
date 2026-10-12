# MD3 规则语法语义清单

来源：legado-with-MD3 commit `d1b488b`，`app/src/main/java/io/legado/app/` 下的源码。2026-10-11 提取，供 Dart 实现逐条对照。【JS】表示 JS 接入点。


源码根目录是 `md3/app/src/main/java/io/legado/app/`。下面的行号如果没写文件名，都指 `model/analyzeRule/AnalyzeRule.kt`。JS 接入点统一标成【JS】，Dart 版先留接口。

### 1. 规则拆分（splitSourceRule / SourceRule）

**第一层：按 JS 片段切段**（539-583）
- `<js>…</js>` 和 `@js:…` 由 `JS_PATTERN` 匹配，忽略大小写（AppPattern.kt:5-6）。`@js:` 可以出现在串中**任意位置**，一直吞到串尾。
- `@webjs:` 后面至少要 5 个字符（AppPattern.kt:7-8）。
- JS 之间的普通片段按 `c <= ' '` 修剪，空段丢弃（555, 576）。
- 各段组成一条**管道**：上一段的输出 `result` 是下一段的输入（getString 334-357）。【JS】Mode.Js 走 `evalJS(rule, result)`（248/342/402/439）；WebJs 走 `getWebJsResult`（173）。

**AllInOne 正则**：只在 `allInOne=true`（getElement / getElements）且首字符是 `:` 时进入 Mode.Regex，并把 `isRegex=true` 设上（545-548）。
- `isRegex` **永不复位**（setContent 也不清，98-110）。此后这个实例上所有新拆的规则都是 Regex 模式（549-550），连 `@css:`、`$.` 这类前缀都不再识别（611）。

**SourceRule 前缀判定**（610-643），按顺序：
1. Js/Regex 模式原样保留。
2. `@CSS:`（忽略大小写）进 Default，**前缀保留**，由 JSoup 层剥掉（AnalyzeByJSoup.kt:516-518，剥完再 trim）。
3. `@@` 进 Default，去掉 2 个字符。
4. `@XPath:` 进 XPath，去掉 7 个字符。
5. `@Json:` 进 Json，去掉 6 个字符。
6. `isJSON || "$." || "$["` 进 Json。
7. 以 `/` 开头（单斜杠就够）进 XPath。
8. 其余进 Default（JSoup）。

关键点：
- 内容是 JSON 时（`isJSON`），任何**无前缀**规则都进 Json 模式，`//a`、`class.x` 也一样。这条判定排在 `/` 判定前面。想在 JSON 内容上强制用 JSoup，只能写 `@@` 或 `@css:`。
- `isJSON` 在 setContent 时算出来（101-104）：Node 视为 false，其余对象取 `toString()` 再判断 `isJson()`。`isJson()` 的规则是 trim 后 `{…}` 或 `[…]`（utils/StringExtensions.kt:47-55）。
  - 所以 Kotlin Map 的 toString（`{a=1}`）和 List 的 toString（`[a, b]`）都会被判成 JSON。

**`@get` / `{{}}` / `$n` 会把整条规则变成模板**（649-657, 690-698）：
- 只要 `@get:{}` 或 `{{}}` 出现在位置 0，或者它前面的文本不含 `##`，模式就改成 Regex。
- 只要 `##` 之前的部分含 `\$\d{1,2}`，模式也改成 Regex。
- Regex 模式在 getString / getStringList 里走 `else -> rule`（351/252），也就是把**拼好的模板字符串当结果**。

**makeUpRule 怎么拼模板**（720-766）：
- `$n`（n≥1）取 `result[n]`，前提是 result 是 List 且 `size > n`。越界或元素为 null 时**插入空**；result 不是 List 时插入字面量 `$n`。
- **`$0` 不会被替换**，因为它的类型码 0 等于字面量类型（706, 763）。
- `@get:{k}` 用 `get(k)` 替换，k 不 trim（667）。
- `{{x}}`：
  - x 以 `@`、`$.`、`$[`、`//` 开头时（782-787），x 作为规则对 **this.content**（不是管道里的 result）求 getString（739-743）。
  - 否则【JS】`evalJS(x, result)`：返回 null 插空；返回整数 Double 时格式化成 `%.0f`；其余 toString（745-755）。
  - 所以 A 类书源只能用前一种写法，`{{key}}` 这种裸变量需要 JS。

### 2. `&&` `||` `%%` 组合运算与 RuleAnalyzer

**切分规则**（RuleAnalyzer.kt:165-237）：
- 分隔符类型由**第一个出现的**运算符决定（elementsType），之后只按这一种切，不支持混用。
- `[]` 和 `()` 里面的分隔符跳过；括号不平衡时 throw `Error("…后未平衡")`（228）。注意这是 Error，不是 Exception。
- `{}` **不受保护**。

**两种平衡函数**：
- 非代码模式（JSoup/XPath）：引号会翻转状态；引号外的 `\` 转义下一个字符（131-159）。
- 代码模式（JSONPath，`code=true`）：`\` 在引号内也转义；只有 `[]` 计深度，`()` 只在 `[]` 深度为 0 时才计（91-126）。

**三种运算符的语义**：
- `&&`：各子结果按顺序拼成一个列表。getString 的最终结果是用 **`"\n"` 连接**，不是直接拼接（JSoup 59，JsonPath 67，XPath 152）。
- `||`：取第一个**非空**子结果后 break（JSoup 106/146/174）。
- `%%`：按下标交错合并，行数以**第一个结果列表的长度**为准，其它列表超出的部分丢弃（JSoup 110-117）。
  - 坑：JSoup 的 `getElements` 会把**空的**子结果也放进列表（AnalyzeByJSoup.kt:145, 173）。所以第一个子规则为空时，`%%` 的结果直接为空。
  - getStringList、JsonPath.getList、XPath 只收非空子结果。
- JsonPath.getString 和 XPath.getString 只切 `&&`、`||`，**不认 `%%`**（AnalyzeByJSonPath.kt:35，AnalyzeByXPath.kt:135）。

### 3. `##` 替换

- makeUpRule 每次都把 rule 按 `"##"` 做普通 split，**保留尾部空串**（769-779）。
  - 第 0 段 trim 后作为规则；第 1 段是 regex，第 2 段是 replacement；**有第 4 段（内容任意）就 replaceFirst=true**。
  - 例：`x##re###` 切成 `["x","re","#"]`，replacement 是 `"#"`，**不是**只替换第一个。
- `###` 模式（496-506）：只返回**第一个匹配子串本身**经替换后的值，匹配之外的内容全部丢掉；没匹配到返回 `""`。正则非法时直接返回 replacement。
- 普通 `##` 模式（509-512）：全局替换。正则编译失败，或替换串非法（Java 的 `$` 语法）时，退化为**字面量**字符串替换。
- replacement 用 **Java 语法**（`$1`、`\` 转义），Dart 需要转换。regex 和 replacement 都不 trim。
- 作用范围：
  - getString：每段管道之后，对 `result.toString()` 整体替换（354-356）。JSoup 多项结果已经用 `\n` 连接，所以正则作用于整个连接串。
  - getStringList：result 是 List 时逐项替换，否则整体替换（255-263）。
  - getElement：对 `result.toString()` 替换（407-409），元素会被转成字符串。
  - **getElements 不调用 makeUpRule**（425-427）：`##`、`{{}}`、`@get` 都不处理，原样传给解析器。
- getString 里规则为空白但带 `##` 时，跳过解析，直接对上游结果做替换（339）。getStringList 判断的是 `isNotEmpty`（243）。

### 4. JSoup 默认语法（AnalyzeByJSoup.kt）

**取值链**：
- 按 `@` 切（RuleAnalyzer 的单分隔符模式，同样跳过括号），先 `trim()` 掉开头的 `@` 和 `<'!'` 字符（RuleAnalyzer.kt:15-22）。
- 最后一段是取值属性，前面各段逐层选元素（200-224）。只有一段时就是对根元素取值，例如 `text`。

**单段选择器 `beforeRule`**（310-322）：
- 为空时取 `children()`。
- 否则 `split(".")`：
  - `children`
  - `class.X` 走 `getElementsByClass`
  - `tag.X` 走 `getElementsByTag`
  - `id.X`
  - `text.X` 走 `getElementsContainingOwnText`（jsoup 里不区分大小写）
  - 其余整段当 CSS 交给 `select`
- **只用 `rules[1]`**：`class.a.b` 等于 `class.a`。
- jsoup 的 getElementsBy* 和 select 结果**包含自身**；Dart 的 `html` 包的 querySelectorAll 不包含自身。

**旧式索引**（482-506），从后往前解析：
- `.N` 表示选取，`!N` 表示排除，`:` 只是**多个索引的列举**，不是区间（如 `tag.li!0:2`）。
- 支持负数。`.` 后面没有数字时 `toInt` 抛异常。

**`[]` 索引**（416-481）：
- `[1,3,-1]`、`[!0,2]` 表示排除，`[start:end:step]` 中两端可省略（start 省略为 0，end 省略为 len-1）。
- 括号里有非数字时（如 `a[href]`）当 CSS 处理。

**索引集合**（324-381）：
- 有序去重，越界的单个索引直接忽略。
- 区间：
  - 负数先加 len；两端在同一侧越界时整段跳过；单端越界时夹到边界。
  - `start==end` 或 `step >= len` 时只取 start。
  - 负 step 换算成 `len + step`，反向区间用 downTo。`[-1:0]` 实现整体反转。
  - 边界情况：len=0 时区间会算出 -1，导致 IndexOutOfBounds。
- 排除模式：先置 null 再 removeAll（386-390）。

**取值属性**（229-280）：
- `text`：`element.text()`（jsoup 规范化空白），空值跳过。
- `textNodes`：每个元素自身的文本节点，逐个 trim、去空后用 `\n` 连接，算一项。
- `ownText`：空值跳过。
- `html`：**先从 DOM 删除 script/style**，然后取所有元素的 `outerHtml` 合成一项。
  - 删除会改动解析缓存，后续规则也受影响（148-157）。
  - jsoup 默认 prettyPrint，会带换行和缩进。
- `all`：outerHtml，空值也加入。
- 其它名字：`attr(name)`，**跳过空白和重复值**。
  - `abs:href` 依赖 baseUri，而 `Jsoup.parse(str)` 没传 baseUri，**通常得到空串**（25-38）。
- **@css: 写法**：
  - getStringList 用 `lastIndexOf('@')` 切出选择器和属性。**没有 `@` 时 substring(0,-1) 抛异常**（95-98）。
  - getElements 直接 `select` 整串（144）。
- 规则为空时返回 `element.data()`（81-83）。
- 解析方式：串以 `<?xml` 开头（忽略大小写，**不 trim**）时用 xmlParser（33）。

### 5. JSONPath（AnalyzeByJSonPath.kt）

- 库是 jayway json-path 3.0.0（gradle/libs.versions.toml:36, 227），用 `JsonPath.parse` 的**默认 Configuration**。
  - 没有 SUPPRESS_EXCEPTIONS：路径不存在时抛异常，被 catch 后得到 `""` 或空列表（51, 88）。
  - `getObject` 不 catch，getElement 会直接抛出（125-127）。
  - provider 默认应是 json-smart，宽松解析；这一点建议在 Dart 端实测核对。
- `{$.x}` 内嵌（41, 79；RuleAnalyzer.kt:308-332）：
  - 用代码平衡找出 `{$.…}`，递归 getString，再拼回模板。
  - **只要有一个替换成功，就返回模板串**；全部失败时才把整条规则当路径读。
  - 结果为空的内嵌保持字面量不替换。
- getString：结果是 List 时用 **`"\n"` 连接**，否则 toString（46-50）。
  - 嵌套对象的 toString 是紧凑 JSON；Dart 必须用 jsonEncode，不能用 Map.toString。
  - JSON null 值的行为待实测：大概率因为 NPE 被吞而得到 `""`，列表里的 null 项会变成 `"null"`（84）。
- getList：`read<ArrayList>`，结果不是数组时 ClassCastException 被吞，返回空列表（137）。

### 6. XPath（AnalyzeByXPath.kt）

- 库是 JsoupXpath 2.5.5（cn.wanghaomiao），底层仍是 jsoup。
- 字符串以 `</td>` 结尾时包一层 `<tr>`；以 `</tr>` 或 `</tbody>` 结尾时包一层 `<table>`（29-34）。
- XML 判断前**会 trim**（36）。
- Element 用 `JXDocument.create(Elements(doc))` 作为上下文（21）。
- getString 用 `TextUtils.join("\n", JXNode)` 连接，结果为空时得到 `""`（137-139）。getStringList 用 `asString()`。
- 元素节点的字符串化依赖库行为（推测是 outerHtml），需要对照验证。

### 7. 正则 AllInOne（AnalyzeByRegex.kt）

- 规则先按 `&&` 用 `splitNotBlank` 普通切开（trim、去空白，**不用 RuleAnalyzer**，见 432）。
- 中间各级：把**所有匹配的 value 无分隔拼接**，作为下一级的输入（50-54）。
- 最后一级：getElements 对每个匹配取 `groupValues[0..n]`，组成 List<String>（40-47），未参与匹配的组是 `""`（Dart 里是 null，要转成 `""`）。getElement 只取第一个匹配（16-18）。
- 列表项是 List<String>，而 `isRegex` 是粘性的，所以后续字段规则都是模板，`$1` 取第 1 组（727-735）。
- 用的是 Java 正则：没有 DOTALL 和 MULTILINE。注意 Dart 不支持占有量词等差异。

### 8. 空值、URL 与格式化

- **getString**：
  - 任一步结果为 null 时，后续步骤都跳过（337），最终得到 `""`（360）。
  - 结果含 `&` 且 `unescape=true` 时做 `unescapeHtml4`（362-366）。正文调用传 `unescape=false`，等格式化之后再反转义（BookContent.kt:234, 244-247）。
  - `isUrl` 且是 Default 模式时，JSoup 用 `getString0`，**只取第一项**（345-346）；Json/XPath 仍然用 `\n` 连接整体。
  - `isUrl` 时：结果为空白返回 `baseUrl ?: ""`，否则 `getAbsoluteURL(redirectUrl, str)`（367-373）。
- **getStringList**：
  - 结果是 String 时按 `"\n"` split，不 trim（268-270）。
  - `isUrl` 时逐项转绝对地址，**丢掉空项并去重**（271-281）。
  - 只有内容为空、规则为空，或某一步返回 null 时才返回 null。
- **getAbsoluteURL**（utils/NetworkUtils.kt:180-195）：
  - 先 trim。base 为 null 时原样返回。
  - http/https（忽略大小写）、data URL 原样返回；`javascript` 开头返回 `""`。
  - 其余用 `java.net.URL(base, rel)` 拼接。
  - **Java URL 不做百分号编码**，中文、空格、legado 的 `url,{json}` 后缀都保持原样；Dart 的 `Uri.resolve` 会编码，这里必须自己写。
- **redirectUrl**：data URL 会被忽略，非法 URL 时保留旧值（119-129）。BookList 直接把 baseUrl 当 redirectUrl 用（BookList.kt:57）。
- **htmlFormat 不在引擎里做**，只在这几个调用方：
  - 搜索简介（BookList.kt:260）
  - 详情简介，以 `<usehtml>`、`<md>`、`<useweb>` 开头的除外（BookInfo.kt:126-135）
  - 正文的 `formatKeepImg`，音频和视频书除外（BookContent.kt:233-244）
  - 规则在 utils/HtmlFormatter.kt:76-86
- **调用方约定**：
  - 列表规则以 `-` 开头表示反转，`+` 开头直接去掉（BookList.kt:90-95）。
  - 章节 url 用的是**不带 isUrl** 的 getString（BookChapterList.kt:237）。

### 9. 变量

- `@put:{k:rule}`：
  - 匹配用 `@put:(\{[^}]+?\})`，忽略大小写，所以**值里不能含 `}`**（955）。
  - JSON 先按严格 Gson 解析，失败再用宽松 Gson（469-483）。
  - 规则串里所有相同的 put 片段都会被删掉（467）。
  - 每次执行这一段都会 `put(k, getString(rule))`，**对 this.content 求值**（455-458）。getElements 里也会执行（426）。
- `put` 只写入第一个非 null 的存储：chapter → book（即 BaseBook 类型的 ruleData）→ ruleData → source（801-807）。
- `get`（812-827）：
  - `bookName` 返回 book.name，`title` 返回 chapter.title。
  - 其余按 chapter → book → ruleData → source 的顺序，取第一个**非空**值，都没有时返回 `""`。
- 长度 ≥10000 的值存进 BigVariable（RuleDataInterface.kt:16-26）。source 变量存在 `CacheManager "v_${key}_${k}"`（data/entities/BaseSource.kt:283-294）。

### 10. 快速路径与缓存

- 内容是 Rhino 的 `NativeObject`（`@js:` 列表规则产出的 JS 对象条目）时，**只取第一个 SourceRule**，管道后面的段被忽略（210-234, 314-330）。
  - 分发顺序：Js 走 evalJS；Json 走 JsonPath；模板（参数数大于 1）返回模板串；其余按**键名直接取值**。
  - 测试锁定了三个行为：`$.name` 返回字段值，`@js:result.name` 会被执行，`getStringList("$.authors")` 返回 `["甲","乙"]`（AnalyzeRuleFastPathReproTest.kt:57-78）。
  - Dart 版对 QuickJS 返回的 Map 条目必须照此分发。
- Gson `LinkedTreeMap`（`@webjs` 列表项）只做键名取值，不走 put、模板和替换（235-236, 331-332）。
- `stringRuleCache` 只按规则字符串做 key，**不分 isJSON / isRegex**（529-533）。SourceRule 对象是可变的，被复用。
  - 同一个实例换了内容类型后，可能沿用旧的模式。
  - `{{}}` 内嵌规则也共用这张表，上限 16（585-588）。
- 列表字段规则在 setContent(item) **之前**就预先拆好（BookList.kt:110-117），所以模式由整页 body 决定。

### 11. 其它容易移植错的细节

- 规则 trim 有三种口径：
  - Kotlin `trim()`（Unicode 空白），用在 `##` 前的规则部分（770）。
  - `c <= ' '`，用在 JS 切段（555）和 findIndexSet（AnalyzeByJSoup.kt:408）。
  - RuleAnalyzer 去掉开头的 `@` 和控制字符。
- JSoup 属性取值去重，`text` 不去重；getStringList 加 isUrl 时还会再去重一次。
- jsoup 版本锁在 1.16.2，原因是上游的破坏性变更（gradle/libs.versions.toml:38-41）。`text()` 和 `ownText()` 的空白规范化、块级元素加空格这些行为，Dart 需要自己复刻。
- 结果数字的 toString（Kotlin 的 `1.0E20` 和 Dart 不同）、JSON 对象序列化格式都要对齐。

### JS 接入点汇总（Dart 先留接口）

| 位置 | 形式 |
|---|---|
| `<js>` / `@js:` 段 | `evalJS(code, result)` |
| `@webjs:` | WebView 执行 |
| `{{非规则}}` | `evalJS`，带 Double 格式化 |
| NativeObject 内容 | 快速路径分发 |
| 规则 JS 的执行环境 | `java` 绑定指向 AnalyzeRule 本身（实现 JsExtensions）；其余绑定：cookie、cache、source、book、result、baseUrl、chapter、title、src、nextChapterUrl、rssArticle、fromBookInfo（832-847） |

两处库行为没法离线核实，需要在 Dart 端写对照用例：JsoupXpath 的 `asString`，以及 json-path 3.0.0 的默认 provider。