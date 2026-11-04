## MODIFIED Requirements

### Requirement: 载入 Legado 书源 JSON
系统 SHALL 接受单个书源对象或书源数组。每个书源以 `bookSourceUrl` 为标识，读出 `bookSourceName`、`bookSourceType`、`header`、`enabledCookieJar`、`concurrentRate`、`bookUrlPattern`、`searchUrl`，以及 `ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent` 四组规则。规则组可以是对象，也可以是内容为 JSON 对象的字符串。缺失的字段和规则组按空处理，不认识的字段忽略，但 MUST 在导出时原样保留。

顶层是对象并且 `sourceUrls` 是数组时，内容是 Legado 的网址列表：载入结果 SHALL 只带回数组里的字符串（书源要从这些网址下载），不载入书源、不报告跳过；即使对象里同时有 `bookSourceUrl`，也按网址列表处理。

#### Scenario: 数组载入
- **WHEN** 载入一个包含 3 个书源的数组
- **THEN** 得到 3 个书源，各自的规则可用

#### Scenario: 规则组是字符串
- **WHEN** 书源的 `ruleSearch` 是字符串 `"{\"bookList\":\"class.item\"}"`
- **THEN** 搜索的列表规则是 `class.item`

#### Scenario: 保留未知字段
- **WHEN** 载入一个带有 `customOrder`、`exploreUrl` 等字段的书源，再导出
- **THEN** 导出的 JSON 里这些字段的值不变

#### Scenario: 网址列表
- **WHEN** 载入 `{"sourceUrls":["https://a.com/1.json","https://a.com/2.json"]}`
- **THEN** 得到 0 个书源、0 个跳过，网址列表是这两个网址

### Requirement: 跳过无效条目
没有 `bookSourceUrl` 的条目和不是 JSON 对象的条目 SHALL 被跳过，载入结果里报告跳过的数量和原因，其余书源照常载入。没有 `bookSourceUrl` 但有 `sourceUrl` 的条目是订阅源，原因 SHALL 写「是订阅源，不是书源」，其余没有 `bookSourceUrl` 的条目写「缺少书源地址」。整个输入不是合法 JSON 时，系统 MUST 以错误结束。

#### Scenario: 混入无效条目
- **WHEN** 数组里有 2 个正常书源和 1 个缺少 `bookSourceUrl` 的条目
- **THEN** 载入 2 个书源，报告跳过 1 个，原因是缺少书源地址

#### Scenario: 混入订阅源
- **WHEN** 数组里有 1 个正常书源和 1 个只有 `sourceUrl`、`sourceName` 的条目
- **THEN** 载入 1 个书源，报告跳过 1 个，原因是「是订阅源，不是书源」
