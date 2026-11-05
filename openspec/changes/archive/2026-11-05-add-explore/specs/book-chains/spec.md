## ADDED Requirements

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
