# rule-syntax Specification

## Purpose

解析 Legado 书源里的规则字符串，从 HTML、JSON 或纯文本内容里取出字符串、字符串列表和元素列表。行为以 legado-with-MD3（commit `d1b488b`）为准，书源作者按 Legado 的实际行为写规则，结果必须和它一致。MD3 在某些输入上会崩溃，这时本能力以明确的错误结束，不让进程崩溃。

## Requirements

### Requirement: 识别取值语法
系统 SHALL 按规则前缀决定取值语法，判定顺序如下：`@css:`（不区分大小写）为 CSS 选择器；`@@` 为 JSoup 默认语法；`@XPath:` 为 XPath；`@json:` 为 JSONPath；当前内容是 JSON（去掉首尾空白后以 `{`…`}` 或 `[`…`]` 包裹）或规则以 `$.`、`$[` 开头时为 JSONPath；以 `/` 开头为 XPath；其余为 JSoup 默认语法。内容是 JSON 时，没有前缀的规则 MUST 一律按 JSONPath 处理，包括以 `/` 开头的规则。

#### Scenario: JSON 内容上的无前缀规则
- **WHEN** 内容是 `{"book":{"name":"三体"}}`，规则是 `book.name`
- **THEN** 按 JSONPath 取值，得到 `三体`

#### Scenario: 用 @@ 强制 JSoup
- **WHEN** 内容是 JSON 字符串 `["<b>x</b>"]`，规则是 `@@tag.b@text`
- **THEN** 不按 JSONPath 处理，按 JSoup 默认语法解析

#### Scenario: / 开头按 XPath
- **WHEN** 内容是 HTML，规则是 `//h1/text()`
- **THEN** 按 XPath 取值

### Requirement: JSoup 默认语法
系统 SHALL 支持 Legado 的 JSoup 默认语法：规则按 `@` 分成若干段，最后一段是取值方式，前面各段逐层选择元素。每段选择器支持 `class.X`、`tag.X`、`id.X`、`text.X`（自身文本包含 X，不区分大小写）、`children`，以及作为 CSS 选择器的其它写法；选择结果 MUST 包含当前元素本身（与 jsoup 的 `select` 一致）。每段末尾支持索引：`.N` 选取、`!N` 排除、`:` 列举多个索引，以及 `[1,3,-1]`、`[!0,2]`、`[start:end:step]` 形式；负数从末尾计。索引越界时忽略该索引。取值方式支持 `text`、`textNodes`、`ownText`、`html`、`all`，其余按属性名取值；属性值 MUST 跳过空白值并去重。

#### Scenario: 逐层选择并取文本
- **WHEN** 内容是 `<div class="list"><a href="/1">一</a><a href="/2">二</a></div>`，规则是 `class.list@tag.a@text`
- **THEN** 字符串列表结果为 `["一","二"]`

#### Scenario: 负索引
- **WHEN** 规则是 `tag.li.-1@text`，内容有 3 个 `li`
- **THEN** 只取最后一个 `li` 的文本

#### Scenario: 区间索引倒序
- **WHEN** 规则是 `tag.li[-1:0]@text`，内容有 3 个 `li`，文本依次是 `a`、`b`、`c`
- **THEN** 字符串列表结果为 `["c","b","a"]`

#### Scenario: 排除索引
- **WHEN** 规则是 `tag.li!0@text`，内容有 3 个 `li`
- **THEN** 结果不含第一个 `li` 的文本

#### Scenario: html 取值去掉脚本和样式
- **WHEN** 规则以 `@html` 结尾，选中的元素里含 `<script>` 和 `<style>`
- **THEN** 结果是元素的 HTML，不含 `<script>`、`<style>` 及其内容

### Requirement: 文本取值与 jsoup 一致
`text` 取值 SHALL 与 jsoup 1.16 的 `Element.text()` 一致：合并连续空白为一个空格，块级元素之间以空格分隔，首尾空白去掉。`ownText` 只取元素自身的直接文本。`textNodes` 取元素自身的每个文本节点，各自去掉首尾空白、丢弃空值后用换行连接。

#### Scenario: 合并空白
- **WHEN** 元素是 `<p>  第一章\n   开始 </p>`，取 `text`
- **THEN** 结果为 `第一章 开始`

#### Scenario: ownText 不含子元素文本
- **WHEN** 元素是 `<p>作者：<a>刘慈欣</a></p>`，取 `ownText`
- **THEN** 结果为 `作者：`

### Requirement: CSS 选择器
以 `@css:` 开头的规则 SHALL 按 CSS 选择器选择元素。取字符串时，规则最后一个 `@` 之后是取值方式。取字符串的 CSS 规则里没有 `@` 时，系统 MUST 以规则错误结束，不得崩溃。

#### Scenario: CSS 取属性
- **WHEN** 规则是 `@css:div.cover > img@src`
- **THEN** 结果是匹配到的 `img` 的 `src` 属性

### Requirement: JSONPath
系统 SHALL 按 Jayway JsonPath 的语义取值：不以 `$` 开头的路径前面补 `$.`；只含单个属性和单个下标的路径（确定路径）取到单个值，其余路径取到值的列表。取字符串时，结果是列表则各项用换行连接；值转字符串的方式与 MD3 一致：对象输出成 `{键=值, …}`，数组输出成紧凑 JSON，小数按 Java 的格式输出（如 `1.0E20`）。路径不存在或值为 null 时结果为空，不报错。取列表时，结果不是数组则为空列表。规则里的 `{$.x}` 片段 SHALL 先各自求值再拼回原文：只要有一个片段取到值，结果就是拼好的文本；所有片段都取不到值时，把整条规则当路径读取。

#### Scenario: 数组结果用换行连接
- **WHEN** 内容是 `{"tags":["玄幻","完本"]}`，规则是 `$.tags[*]`，取字符串
- **THEN** 结果为 `玄幻\n完本`

#### Scenario: 内嵌路径拼接
- **WHEN** 内容是 `{"id":42}`，规则是 `/book/{$.id}.html`
- **THEN** 结果为 `/book/42.html`

#### Scenario: 对象转字符串
- **WHEN** 内容是 `{"book":{"id":1,"name":"三体"}}`，规则是 `$.book`，取字符串
- **THEN** 结果为 `{id=1, name=三体}`

#### Scenario: 路径不存在
- **WHEN** 规则是 `$.missing`
- **THEN** 字符串结果为空，不报错

### Requirement: XPath
系统 SHALL 按 JsoupXpath 2.5.5（MD3 用的 XPath 库）的语义取值，它和标准 XPath 1.0 有差别：绝对和相对路径、`//`（之后的名字测试包含上下文元素本身）、`.`、`..`、`*`、`@name`；节点测试 `text()`（得到合并空白、去掉首尾空白的文本）、`node()`、`allText()`、`html()`、`outerHtml()`、`num()`；轴 `child`、`descendant`、`descendant-or-self`、`parent`、`ancestor`、`ancestor-or-self`、`following`、`following-sibling`、`preceding`、`preceding-sibling`、`self`、`following-sibling-one`、`preceding-sibling-one`；谓词里的序号按上下文中同名的兄弟元素计数，负数从末尾计；比较运算和 `^=`、`$=`、`*=`、`~=`、`!~`、`and`、`or`；函数 `position()`、`last()`、`count()`、`not()`、`contains()`、`starts-with()`、`concat()`、`string-length()`、`substring()` 系列、`sum()`、`first()`；路径并集 `|`。取字符串时多个结果用换行连接，元素结果输出它的 HTML。遇到 JsoupXpath 不支持的写法（如 `normalize-space()`、`translate()`）时，系统 MUST 以「不支持的 XPath」错误结束。

#### Scenario: 取 meta 属性
- **WHEN** 规则是 `//meta[@property='og:title']/@content`
- **THEN** 结果是该 meta 的 `content` 属性值

#### Scenario: 谓词组合
- **WHEN** 规则是 `//div[@class='desc' and @itemprop='description']/text()`
- **THEN** 只取同时满足两个属性条件的 div 的文本

#### Scenario: 不支持的语法
- **WHEN** 规则使用了子集以外的函数，例如 `//a[translate(.,'a','b')]`
- **THEN** 以「不支持的 XPath」错误结束

### Requirement: 组合运算符
一条规则 SHALL 支持 `&&`（各子规则结果按顺序合并）、`||`（取第一个非空的子规则结果）、`%%`（按下标交错合并，行数以第一个子规则结果为准）。运算符种类由规则里第一个出现的运算符决定，`[]`、`()` 和引号内的运算符不参与切分。合并后取字符串时各项用换行连接。括号不配对时，系统 MUST 以规则错误结束。

#### Scenario: || 取第一个非空
- **WHEN** 规则是 `class.a@text||class.b@text`，内容里没有 `.a`，有 `.b`
- **THEN** 结果取自 `.b`

#### Scenario: %% 交错合并
- **WHEN** 规则是 `tag.h3@text%%tag.p@text`，h3 依次为 `A1`、`A2`，p 依次为 `B1`、`B2`、`B3`
- **THEN** 字符串列表结果为 `["A1","B1","A2","B2"]`

#### Scenario: 括号里的运算符不切分
- **WHEN** 规则是 `$.list[?(@.a && @.b)].name`
- **THEN** 不在 `&&` 处切分，整条作为一个 JSONPath

### Requirement: 正则净化
规则末尾的 `##正则##替换` SHALL 对取到的结果做正则替换：默认替换全部匹配；切分后有第 4 段（即写成 `##正则##替换###`）时，只取第一个匹配，结果是这个匹配替换后的文本，没有匹配时为空。替换文本按 Java 语法解释（`$1` 引用分组，`\` 转义）。取字符串时替换作用于整个结果；取列表时逐项替换。正则无法编译或替换文本非法时，系统 SHALL 退化为字面量替换。

#### Scenario: 删除广告
- **WHEN** 规则是 `id.content@text##请记住本站.*`，正文末尾有「请记住本站域名」
- **THEN** 结果不含「请记住本站」及其后的内容

#### Scenario: 只取第一个匹配
- **WHEN** 净化部分是 `##(\d+)章##第$1章###`，净化前的文本是 `共 12章 / 34章`
- **THEN** 结果为 `第12章`

#### Scenario: 非法正则退化为字面量
- **WHEN** 净化部分是 `##[未闭合`，净化前的文本含 `[未闭合`
- **THEN** 把 `[未闭合` 作为普通字符串删除，不报错

### Requirement: 书源正则可以被中止
书源提供的所有正则（净化、AllInOne 正则、`bookUrlPattern`、`replaceRegex`）SHALL 在能响应任务中止信号的引擎里执行。任务被取消或超时后，正在执行的正则 MUST 在有限时间内停下，worker 不需要被放弃。

#### Scenario: 灾难性回溯被取消
- **WHEN** 净化正则是 `(a+)+b`，作用在 30 个 `a` 组成的文本上，执行中任务被取消
- **THEN** 提交方收到取消错误，worker 在宽限期内结束任务，没有被放弃

### Requirement: AllInOne 正则
以 `:` 开头的列表规则 SHALL 按正则取列表：按 `&&` 分级，前面各级把所有匹配直接拼接作为下一级的输入，最后一级的每个匹配是列表中的一项，项的内容是该匹配的全部分组（未参与匹配的分组为空串）。之后各字段规则里的 `$1`、`$2` 等引用当前项的对应分组。

#### Scenario: 正则列表与分组引用
- **WHEN** 列表规则是 `:<a href="(.*?)">(.*?)</a>`，书名规则是 `$2`，地址规则是 `$1`
- **THEN** 每个链接成为一项，书名取链接文字，地址取 href

### Requirement: 变量与内嵌规则
规则里的 `@put:{键:规则}` SHALL 对当前内容求值并保存变量；`@get:{键}` SHALL 读取变量，按章节、书籍、本次链路的顺序取第一个非空值，都没有时为空串。`{{x}}` 中 x 以 `@`、`$.`、`$[`、`//` 开头时，x 作为规则对当前内容求值后拼回原文；其余情况 x 作为 JS 求值（见 source-js），结果拼回原文：结果为 null 时不拼入，整数值的数字不带小数点。`{{baseUrl}}`、`{{title}}` 这类只有变量名的写法按 JS 求值，与读取注入变量的结果相同。`@get:{bookName}` 和 `@get:{title}` 分别读取书名和章节名。规则里只要出现 `{{}}` 或 `@get:{}`，并且第一处出现在规则开头或它前面没有 `##`，整条规则 SHALL 作为模板，结果就是拼好的文本，不再作为选择器取值。变量 SHALL 随书籍和章节的结果返回，供后续链路读取。

#### Scenario: 详情页保存、目录页读取
- **WHEN** 详情规则含 `@put:{bid:$.id}`，目录地址规则是 `/toc/@get:{bid}`
- **THEN** 目录请求的地址里是详情页取到的 id

#### Scenario: 内嵌规则拼接
- **WHEN** 规则是 `{{$.title}} 作者 {{$.author}}`，内容是 `{"title":"三体","author":"刘慈欣"}`
- **THEN** 结果为 `三体 作者 刘慈欣`

#### Scenario: 内嵌 JS 表达式
- **WHEN** 简介规则是 `{{'《' + book.name + '》'}}`，书名是 `三体`
- **THEN** 结果为 `《三体》`

### Requirement: 需要 WebView 时明确报错
规则里出现 `@webjs:` 时，系统 SHALL 以「需要 WebView」错误结束，错误里带有出错的规则片段。系统 MUST NOT 跳过这个片段继续求值。

#### Scenario: 规则里有 @webjs:
- **WHEN** 正文规则是 `@webjs:document.body.innerText`
- **THEN** 以「需要 WebView」错误结束，错误里带有 `@webjs:document.body.innerText`

### Requirement: 地址取值
规则用于取地址时，系统 SHALL 把相对地址按当前页面的最终地址（重定向之后）转成绝对地址，`http`、`https`、`data:` 开头的保持原样，`javascript` 开头的视为空。拼接 MUST NOT 对地址做百分号编码，中文、空格和 Legado 的 `,{选项}` 后缀保持原样。规则非空但取到空白时，结果为当前页面地址。取地址列表时 MUST 去掉空项并去重。JSoup 默认语法取单个地址时只取第一个结果。

#### Scenario: 相对地址
- **WHEN** 当前页面最终地址是 `https://a.com/book/1/`，取到的地址是 `../2/`
- **THEN** 结果为 `https://a.com/book/2/`

#### Scenario: 不编码中文
- **WHEN** 当前页面是 `https://a.com/s`，取到的地址是 `/search?k=三体`
- **THEN** 结果为 `https://a.com/search?k=三体`，中文没有被编码
