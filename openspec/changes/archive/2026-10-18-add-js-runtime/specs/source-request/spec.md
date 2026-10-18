## ADDED Requirements

### Requirement: 登录检查 JS
书源有 `loginCheckJs` 时，每次链路请求得到响应后，系统 SHALL 以响应对象为 `result` 执行它（`java` 是这次请求的 URL 上下文对象），用它返回的响应对象代替原响应继续处理。JS 里可以调用 `java.getStrResponse()` 重新发出这次请求。返回值不是响应对象时，链路 MUST 以错误结束。

#### Scenario: 检查后重新请求
- **WHEN** `loginCheckJs` 是 `result.body().includes('请登录') ? java.getStrResponse() : result`，第一次响应正文含「请登录」，第二次不含
- **THEN** 系统重新请求一次，用第二次的响应继续解析

#### Scenario: 返回了字符串
- **WHEN** `loginCheckJs` 是 `result.body()`
- **THEN** 链路以错误结束

## MODIFIED Requirements

### Requirement: URL 模板
系统 SHALL 按以下顺序处理请求地址：依次执行地址里的 `@js:`、`<js>…</js>` 段（`result` 是到这一段为止的地址文本，普通文本段里的 `@result` 换成上一段的结果，返回值转成文本作为新的地址）；替换 `{{…}}`：每个 `{{` 到它之后的第一个 `}}` 之间的内容一律作为 JS 求值（`{{key}}`、`{{page}}`、`{{baseUrl}}` 也是读取注入变量），结果为 null 时替换成空串，整数值的数字不带小数点，替换后整个地址为空时保留原地址；处理 `<a,b,c>` 页码列表；切出地址后面的 `,{选项}`；把地址按传入的基准地址转成绝对地址。搜索词在这一步原样插入，不编码。页码列表在第 n 页取第 n 项，页码超过项数时取最后一项。

#### Scenario: 搜索地址
- **WHEN** 搜索地址是 `/search?q={{key}}&p={{page}}`，搜索词是 `三体`，第 2 页，书源地址是 `https://a.com`
- **THEN** 请求地址是 `https://a.com/search?q=三体&p=2` 编码之后的形式

#### Scenario: 页码列表
- **WHEN** 地址是 `/list<,_2,_3>.html`，分别请求第 1、2、5 页
- **THEN** 地址依次为 `/list.html`、`/list_2.html`、`/list_3.html`

#### Scenario: 模板里有表达式
- **WHEN** 地址是 `/s?p={{(page-1)*10}}`，第 3 页
- **THEN** 请求地址是 `/s?p=20`

#### Scenario: 地址整体由 JS 生成
- **WHEN** 搜索地址是 `@js:'/s/' + encodeURIComponent(key) + ',{"method":"POST","body":"k=' + key + '"}'`，搜索词是 `a`
- **THEN** 发出 POST 请求，地址是 `/s/a`，请求体是 `k=a`

### Requirement: URL 选项
地址后面的 `,{…}` SHALL 解析为请求选项，先按严格 JSON 解析，失败再按宽松语法（单引号、不带引号的键）解析，仍然失败时按没有选项处理。支持的选项：`method`（只认 POST、HEAD，其余按 GET）、`headers`（对象或 JSON 字符串，覆盖书源请求头）、`body`（字符串原样使用；对象或数组序列化为带缩进的 JSON）、`charset`（请求参数的编码）、`retry`（非 2xx 响应的重试次数，默认 0）、`type`（不为空时返回响应字节的十六进制字符串）、`js`（地址转成绝对地址之后执行，`result` 是绝对地址，返回值不为 null 时作为新的地址；JS 里可以通过 `java.headerMap` 修改请求头）、`bodyJs`（拿到响应之后执行，`result` 是响应正文，返回值转成文本作为新的正文，null 转成字符串 `null`）。`webView` 为真（`null`、空串、`false`、`"false"` 以外的值，数字 0 也算真）时，MUST 以「需要 WebView」错误结束；`webJs` 只在使用 WebView 时生效，单独出现时忽略。

#### Scenario: 宽松 JSON 选项
- **WHEN** 地址是 `/search,{'method':'POST','body':'q={{key}}'}`
- **THEN** 发出 POST 请求，请求体是 `q=` 加编码后的搜索词

#### Scenario: webView 选项
- **WHEN** 地址选项里有 `"webView": true`
- **THEN** 以「需要 WebView」错误结束，不发请求

#### Scenario: js 选项改请求头
- **WHEN** 地址选项是 `{"js":"java.headerMap.put('X-Sign', java.md5Encode(result)); result"}`
- **THEN** 请求带有 `X-Sign` 头，值是绝对地址的 MD5

#### Scenario: bodyJs 解密正文
- **WHEN** 地址选项是 `{"bodyJs":"java.base64Decode(result)"}`，响应正文是 `5LiJ5L2T`
- **THEN** 规则拿到的内容是 `三体`

### Requirement: 请求头
系统 SHALL 用书源的 `header` 字段作为请求头，再叠加登录头和 URL 选项里的 `headers`。`header` 以 `@js:` 或 `<js>` 开头（不区分大小写）时，SHALL 以书源级上下文执行这段 JS，每次构造请求都执行一次，结果按严格或宽松 JSON 解析为请求头；JS 出错时 MUST 只记录日志，按没有书源请求头处理，请求照常发出。没有 User-Agent 时补默认的桌面 Chrome UA；User-Agent 的值是 `null` 时不发送 UA。

#### Scenario: 书源请求头
- **WHEN** 书源 `header` 是 `{"Referer":"https://a.com/"}`
- **THEN** 请求带有该 Referer 和默认 UA

#### Scenario: 请求头由 JS 生成
- **WHEN** 书源 `header` 是 `@js:JSON.stringify({'X-Src': source.getKey()})`
- **THEN** 请求带有 `X-Src` 头，值是书源地址

#### Scenario: 请求头 JS 出错
- **WHEN** 书源 `header` 是 `@js:throw 1`
- **THEN** 请求照常发出，只带默认 UA，日志接收方收到这次错误
