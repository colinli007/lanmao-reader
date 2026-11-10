# book-chains Specification

## Purpose

把书源规则串成搜索、详情、目录、正文四条链路：输入书源和上一步的结果，输出下一步需要的数据。链路在后台 worker 里同步执行，可以取消。行为以 legado-with-MD3（commit `d1b488b`）为准。

## Requirements

### Requirement: 链路在 worker 中执行
四条链路 SHALL 作为任务提交到工作 isolate 池执行，提交方异步拿到结果。输入和输出都 MUST 能在 isolate 之间传递。链路 SHALL 在每次请求之前和处理每一页之后检查取消，任务被取消或超时时尽快以对应错误结束。链路需要但本能力不支持的部分（不支持的宿主 API、WebView）以对应的错误结束；JS 出错时以 JS 错误结束；错误里带有书源名和出错的字段。

#### Scenario: 取消一次搜索
- **WHEN** 同一个取消令牌下有 20 个书源的搜索任务，令牌被触发
- **THEN** 20 个提交方都收到取消错误

#### Scenario: 错误指出字段
- **WHEN** 某书源的目录章节名规则是 `@js:java.getVerificationCode(result)`
- **THEN** 目录链路以「不支持的宿主 API」错误结束，错误里有书源名和 `ruleToc.chapterName`

### Requirement: 搜索
搜索 SHALL 请求搜索地址，用列表规则取出结果项，对每一项取书名、作者、分类、字数、最新章节、简介、封面和书籍地址：
- 书名去掉「作者」等后缀并去掉首尾空白，书名为空的项丢弃；作者去掉「作者：」前缀和「著」后缀；
- 分类取列表后用逗号连接；字数是纯整数时格式化（大于 1 万为「x.x万字」，否则为「x字」）；
- 封面和书籍地址转成绝对地址，书籍地址为空时取搜索页地址；
- 结果按书籍地址去重，保留第一次出现的项；
- 列表规则以 `-` 开头时，去重后整体倒序；以 `+` 开头时去掉这个前缀。

书名、作者、书籍地址的规则出错时整次搜索以错误结束；其余字段出错时该字段为空。

#### Scenario: 正常搜索
- **WHEN** 搜索页有 3 个结果，其中一个书名为空
- **THEN** 返回 2 个结果，书籍地址都是绝对地址

#### Scenario: 清洗书名和作者
- **WHEN** 取到的书名是 `三体 作者：刘慈欣`，作者是 `作者：刘慈欣`
- **THEN** 书名为 `三体`，作者为 `刘慈欣`

### Requirement: 搜索结果直接是详情页
搜索响应的最终地址与书源的 `bookUrlPattern` 整串匹配时，或者列表为空且书源没有设置 `bookUrlPattern` 时，系统 SHALL 把搜索页当作详情页解析，返回一个结果；该结果的书籍地址是最终地址，并保存这个页面，随后的详情链路 MUST NOT 再请求一次。列表为空但设置了 `bookUrlPattern` 且不匹配时，返回空列表。

#### Scenario: 搜索被重定向到详情页
- **WHEN** 搜索请求被重定向到 `https://a.com/book/1.html`，`bookUrlPattern` 是 `https://a\.com/book/\d+\.html`
- **THEN** 返回一个按详情规则解析的结果，接着执行详情链路时不发请求

### Requirement: 详情
详情链路 SHALL 请求书籍地址（已有保存的页面时直接使用），先按 `init` 规则取出详情所在的元素，之后的字段在这部分内容上取值（和 MD3 一样，JSoup 规则取到的元素列表转成 HTML 后重新解析，取不到时得到空内容；正则或 JSONPath 规则取不到时以错误结束），再取各字段：书名和作者只在书籍原来没有值，或详情规则的 `canReName` 非空时写入；分类、字数、最新章节、封面只在取到非空值时覆盖；简介以 `<usehtml>`、`<md>`、`<useweb>` 开头时原样保留，否则去掉 HTML 标签并截取前 5000 字。目录地址为空时取书籍地址；目录地址等于书籍地址时保存详情页，目录链路 MUST NOT 再请求一次。

#### Scenario: 目录就在详情页
- **WHEN** 书源没有目录地址规则
- **THEN** 目录地址等于书籍地址，目录链路直接解析详情页，不发请求

#### Scenario: init 取不到
- **WHEN** `init` 规则是 AllInOne 正则 `:<div class="info">(.*?)</div>`，页面里没有匹配
- **THEN** 详情链路以错误结束，错误指出 `ruleBookInfo.init`

#### Scenario: JSoup 的 init 取不到
- **WHEN** `init` 规则是 `class.book-info`，页面里没有这个元素
- **THEN** 和 MD3 一样不报错，之后的字段取到空值

### Requirement: 目录
目录链路 SHALL 用列表规则取出章节，对每章取章节名、章节地址（相对当前页，到正文链路才转成绝对地址）、是否为卷、是否 VIP、是否付费、更新时间。布尔字段为空白、`null`，或匹配 `false`、`no`、`not`、`0`、`0.0`（不区分大小写）时为假，其余为真。章节名为空的丢弃；章节地址为空时，卷用「章节名 + 本页序号」，普通章节用当前页地址。章节按地址去重时保留最后一次出现的；列表规则以 `-` 开头时整体倒序。结果为空时 MUST 以「目录为空」错误结束。

#### Scenario: 卷与章节
- **WHEN** 目录页有 1 个卷名（无链接）和 3 个章节，卷的 `isVolume` 规则取到 `1`
- **THEN** 返回 4 项，第一项是卷，地址为「卷名 + 序号」

#### Scenario: 空目录
- **WHEN** 列表规则一个章节都取不到
- **THEN** 以「目录为空」错误结束

### Requirement: 多页目录
下一页规则取到 1 个地址时，系统 SHALL 逐页串行翻页，每页只取第一个下一页地址，访问过的地址不再访问，取不到时停止。取到多个地址时，系统 SHALL 只用首页给出的这一批地址并发请求，子页不再找下一页，章节按页面顺序合并。

#### Scenario: 串行翻页防循环
- **WHEN** 第 3 页的下一页地址指回第 1 页
- **THEN** 翻到第 3 页后停止，目录不重复

#### Scenario: 首页列出全部分页
- **WHEN** 首页的下一页规则取到 4 个分页地址
- **THEN** 并发请求这 4 页，章节顺序为首页、分页 1 到分页 4

### Requirement: 目录的 formatJs
目录规则有 `formatJs` 时，目录链路 SHALL 在得到全部章节后逐章执行它，注入 `gInt`（初始为 0）、`index`（从 1 开始的序号）、`chapter`、`title`，不注入 `java`、`source`、`book`，也不挂 jsLib；返回值不为 null 时转成文本作为章节名，为 null 时章节名不变。`formatJs` 的所有章节共用一个变量层，`gInt` 和未声明变量的修改在章节之间累积。某一章执行出错时 SHALL 只记录日志，这一章的章节名不变，其余章节照常处理。`preUpdateJs` 只在 MD3 更新书架书籍的目录时执行，不属于目录链路，本能力忽略它。

#### Scenario: 给章节加序号
- **WHEN** `formatJs` 是 `index + '. ' + title`，目录有「序章」「第一章」两章
- **THEN** 章节名依次为 `1. 序章`、`2. 第一章`

#### Scenario: 跨章节累积
- **WHEN** `formatJs` 是 `gInt++; gInt + title`，目录有三章
- **THEN** 三章的章节名分别以 `1`、`2`、`3` 开头

### Requirement: 正文
正文链路 SHALL 请求章节的绝对地址（相对目录页地址计算，保留 `,{选项}`），用正文规则取出 HTML，格式化为纯文本：`&nbsp;` 等空白实体转为空格，去掉零宽字符和注释，块级标签（div、p、br、hr、h1 到 h6、article、dd、dl）转为换行，去掉 img 以外的标签，每段行首加两个全角空格；img 的 `src`、`data-src` 转成绝对地址并保留；最后反转义 HTML 实体。`replaceRegex` 规则逐行去掉首尾空白后整体替换，再给每行加缩进。正文规则为空时，结果是章节地址。正文为空白时 MUST 以「正文为空」错误结束。

#### Scenario: 格式化段落
- **WHEN** 取到的正文是 `<p>第一段</p><p>第二段&nbsp;</p><script>x</script>`
- **THEN** 结果是两段，每段以两个全角空格开头，不含标签和脚本内容

#### Scenario: 净化广告行
- **WHEN** `replaceRegex` 是 `##.*本站.*`，正文某一行是「请收藏本站」
- **THEN** 该行内容被删除

### Requirement: 多页正文
下一页规则取到 1 个地址时，系统 SHALL 串行翻页；翻页前，如果这个地址（转成绝对地址后）等于下一章的地址，就停止翻页。取到多个地址时，并发请求这一批地址，不做下一章判断。各页正文用换行连接后再格式化。

#### Scenario: 遇到下一章停止
- **WHEN** 正文第 2 页的「下一页」链接指向下一章的地址
- **THEN** 只合并前 2 页，不把下一章的内容并进来

#### Scenario: 正文分 3 页
- **WHEN** 一章正文分 3 页，每页都有指向下一页的链接，第 3 页的链接指向下一章
- **THEN** 结果是 3 页正文按顺序合并

### Requirement: 分段搜索
搜索 SHALL 可以分两段执行：
- 第一段构造搜索请求，交回提交方。地址规则里的 JS、书源请求头的 JS 在这一段执行。
- 提交方发出请求，把响应交给第二段。
- 第二段处理响应，得到结果。选项 `bodyJs`、`loginCheckJs`、列表规则在这一段执行。

两段 MAY 在不同的 worker 上执行，第一段交回的内容 MUST 能在 isolate 之间传递。

分两段执行时，每段里的 JS 只执行一次。结果、书源 JS 写的日志、书源级状态的读写、错误（包括书源名和字段）SHALL 和一次执行相同。请求失败时，这次搜索以网络错误结束，错误原因和一次执行时相同。

#### Scenario: 两段执行和一次执行结果相同
- **WHEN** 对同一个书源和同一份录制的搜索响应，分别一次执行、分两段在两个不同的 worker 上执行
- **THEN** 两次的结果相同

#### Scenario: 地址里的 JS 只执行一次
- **WHEN** 搜索地址是 `@js:java.log('构造');'/search?q='+key`，分两段执行
- **THEN** 书源日志里「构造」只有一条

#### Scenario: 第二段执行 loginCheckJs
- **WHEN** 书源的 `loginCheckJs` 是 `result.body().includes('请登录') ? java.getStrResponse() : result`，分两段执行，第一次响应正文含「请登录」，第二次不含
- **THEN** 第二段重新发出同一个搜索请求，结果按第二次的响应解析

### Requirement: 正文图片
系统 SHALL 可以按书源取正文里的一张图片，在 worker 中执行，结果是图片的字节：

- 地址以 `data:` 开头时，不发请求：匹配 `data:…;base64,数据` 的，按 Android `Base64.DEFAULT` 解码数据（和 source-request「URL 选项」的 `data:` 地址相同）；不匹配时 MUST 以错误结束。
- 其余地址（正文链路已经转成绝对地址，可能带 `,{选项}`）按书源构造请求：带书源的请求头和 Cookie，处理选项（请求头、方法等），和正文链路的请求相同；取响应的原始字节。响应状态码不是 2xx 时 MUST 以错误结束。
- 书源的 `ruleContent.imageDecode` 不为空时，SHALL 用书源级的 JS 上下文执行它，`book` 是书籍，`result` 是上一步的字节，`src` 是图片地址；返回值（字节数组或文本）作为图片的字节。返回 null 时 MUST 以错误结束。

#### Scenario: 带书源请求头
- **WHEN** 书源的 `header` 是 `{"Referer":"https://a.com/"}`，图片地址是 `https://img.a.com/1.jpg`
- **THEN** 请求带 `Referer: https://a.com/`，结果是响应的字节

#### Scenario: 解密图片
- **WHEN** 书源的 `imageDecode` 是把 `result` 的每个字节和 1 异或后返回
- **THEN** 结果是响应字节逐个异或 1 之后的字节

#### Scenario: data 地址
- **WHEN** 图片地址是 `data:image/png;base64,iVBORw0KGgo=`
- **THEN** 不发请求，结果是解码后的 8 个字节

#### Scenario: 404
- **WHEN** 图片请求返回 404
- **THEN** 以错误结束

### Requirement: 发现分类
系统 SHALL 可以算出一个书源的发现分类，在 worker 中执行。书源的 `exploreUrl` 为空时没有分类。

- `exploreUrl` 以 `<js>` 或 `@js:` 开头（不区分大小写）时，SHALL 先用书源级的 JS 上下文执行（`@js:` 取后面的全部，`<js>` 取到最后一个 `<` 之前），返回值转成文本、去掉首尾空白，再按下面两条解析。
- 文本以 `[` 开头、`]` 结尾时，SHALL 按宽松 JSON 数组解析，每个对象是一个分类：
  - `title`（缺少时为空）、`url`（可以为空）、`type`（缺少时是 `url`）。
  - `style` 里的 `layout_flexGrow`（默认 0）、`layout_flexShrink`（默认 1）、`layout_flexBasisPercent`（默认 -1）、`layout_wrapBefore`（默认 false）。
  - 数值是数字或数字文本都可以，读不出时用默认值。数组里不是对象的项跳过。
  - 解析失败时 MUST 以错误结束。
- 其余文本 SHALL 按正则 `(&&|\n)+` 拆成多段，每段按 `::` 拆开，第一段是标题，第二段（没有时为空）是地址，类型是 `url`、样式取默认值。
- JS 出错时 MUST 以错误结束。

#### Scenario: JSON 数组
- **WHEN** `exploreUrl` 是 `[{"title":"玄幻","url":"/xh/{{page}}","style":{"layout_flexBasisPercent":0.25,"layout_flexGrow":1}},{"title":"排行"}]`
- **THEN** 有两个分类：「玄幻」地址 `/xh/{{page}}`、宽度比例 0.25、伸展 1；「排行」没有地址

#### Scenario: 文本
- **WHEN** `exploreUrl` 是 `玄幻::/xh/{{page}}&&都市::/ds/{{page}}`
- **THEN** 有「玄幻」「都市」两个分类，地址分别是 `/xh/{{page}}`、`/ds/{{page}}`

#### Scenario: JS 生成
- **WHEN** `exploreUrl` 是 `@js:JSON.stringify([{title:"最新",url:"/new"}])`
- **THEN** 有一个分类「最新」，地址 `/new`

#### Scenario: JS 出错
- **WHEN** `exploreUrl` 是 `@js:throw new Error("x")`
- **THEN** 以错误结束

### Requirement: 发现
系统 SHALL 按书源、分类地址和页码取一页书籍列表，在 worker 中执行：

- 用分类地址构造请求，页码是给定的页码，baseUrl 是书源地址，和搜索链路的请求相同（书源请求头、Cookie、`,{选项}`、URL 里的 JS）。
- 收到响应后执行书源的 `loginCheckJs`。
- 书籍列表规则：书源 `ruleExplore` 的 `bookList` 不为空时用 `ruleExplore`，否则用 `ruleSearch`。各字段的取法、去重、倒序和搜索相同。
- MUST NOT 判断 `bookUrlPattern`：响应地址匹配它时也按列表解析。
- 列表为空且书源没有 `bookUrlPattern` 时，按详情页解析成一个结果，和搜索相同。

#### Scenario: 用 ruleExplore
- **WHEN** 书源有 `ruleExplore.bookList`，分类地址是 `/xh/{{page}}`，页码是 2
- **THEN** 请求 `书源地址/xh/2`，用 `ruleExplore` 的规则解析出书籍列表

#### Scenario: ruleExplore 没有列表规则
- **WHEN** 书源的 `ruleExplore` 为空
- **THEN** 用 `ruleSearch` 的规则解析
