# source-request Specification

## Purpose

根据书源配置和 URL 模板构造 HTTP 请求，在主 isolate 上执行，把响应解码成文本交给规则引擎。行为以 legado-with-MD3（commit `d1b488b`）为准。所有 worker 共用一份 Cookie，以后 JS 里的网络请求也走同一条路。

## Requirements

### Requirement: URL 模板
系统 SHALL 按以下顺序处理请求地址：替换 `{{key}}`（搜索词）、`{{page}}`（页码）、`{{baseUrl}}`；处理 `<a,b,c>` 页码列表；切出地址后面的 `,{选项}`；把地址按传入的基准地址转成绝对地址。搜索词在这一步原样插入，不编码。页码列表在第 n 页取第 n 项，页码超过项数时取最后一项。`{{}}` 里出现其它内容时，系统 MUST 以「需要 JS 引擎」错误结束。

#### Scenario: 搜索地址
- **WHEN** 搜索地址是 `/search?q={{key}}&p={{page}}`，搜索词是 `三体`，第 2 页，书源地址是 `https://a.com`
- **THEN** 请求地址是 `https://a.com/search?q=三体&p=2` 编码之后的形式

#### Scenario: 页码列表
- **WHEN** 地址是 `/list<,_2,_3>.html`，分别请求第 1、2、5 页
- **THEN** 地址依次为 `/list.html`、`/list_2.html`、`/list_3.html`

#### Scenario: 模板里有表达式
- **WHEN** 地址是 `/s?p={{page*10}}`
- **THEN** 以「需要 JS 引擎」错误结束

### Requirement: URL 选项
地址后面的 `,{…}` SHALL 解析为请求选项，先按严格 JSON 解析，失败再按宽松语法（单引号、不带引号的键）解析，仍然失败时按没有选项处理。支持的选项：`method`（只认 POST、HEAD，其余按 GET）、`headers`（对象或 JSON 字符串，覆盖书源请求头）、`body`（字符串原样使用；对象或数组序列化为带缩进的 JSON）、`charset`（请求参数的编码）、`retry`（非 2xx 响应的重试次数，默认 0）、`type`（不为空时返回响应字节的十六进制字符串）。`js`、`bodyJs` 选项 MUST 以「需要 JS 引擎」错误结束；`webView` 为真（`null`、空串、`false`、`"false"` 以外的值，数字 0 也算真）时，MUST 以「需要 WebView」错误结束；`webJs` 只在使用 WebView 时生效，单独出现时忽略。

#### Scenario: 宽松 JSON 选项
- **WHEN** 地址是 `/search,{'method':'POST','body':'q={{key}}'}`
- **THEN** 发出 POST 请求，请求体是 `q=` 加编码后的搜索词

#### Scenario: webView 选项
- **WHEN** 地址选项里有 `"webView": true`
- **THEN** 以「需要 WebView」错误结束，不发请求

### Requirement: 请求参数编码
GET 请求的查询串已经是合法的百分号编码时，系统 SHALL 原样发送；否则逐字符编码：安全字符保留，其余字符按 `charset` 选项（默认 UTF-8）转成字节，输出大写的 `%XX`，空格编码为 `%20`。`charset` 为 `escape` 时，按 JS `escape()` 的规则编码每个参数值。POST 请求体不像 JSON 或 XML、也没有指定 Content-Type 时，系统 SHALL 按表单编码（空格编码为 `+`）发送；指定了 Content-Type 时原样发送；其余情况按 `application/json; charset=UTF-8` 发送。系统 MUST 支持 GBK 和 GB2312。

#### Scenario: GBK 搜索词
- **WHEN** 搜索地址是 `/s?q={{key}},{"charset":"gbk"}`，搜索词是 `三体`
- **THEN** 查询串是 `q=%C8%FD%CC%E5`

#### Scenario: 已编码的查询串
- **WHEN** 查询串是 `q=%E4%B8%89`
- **THEN** 原样发送，不重复编码

### Requirement: 请求头
系统 SHALL 用书源的 `header` 字段（严格或宽松 JSON）作为请求头，再叠加 URL 选项里的 `headers`。没有 User-Agent 时补默认的桌面 Chrome UA；User-Agent 的值是 `null` 时不发送 UA。`header` 以 `@js:` 或 `<js>` 开头时，系统 MUST 以「需要 JS 引擎」错误结束。

#### Scenario: 书源请求头
- **WHEN** 书源 `header` 是 `{"Referer":"https://a.com/"}`
- **THEN** 请求带有该 Referer 和默认 UA

### Requirement: 网络请求在主 isolate 上执行
worker 里的规则引擎 SHALL 通过阻塞桥把请求交给主 isolate 执行，并同步等待结果。主 isolate 返回响应的原始字节、最终地址和响应头，解码在 worker 里完成。规则引擎需要同时请求多个地址时（多页目录、多页正文），SHALL 一次提交整批请求，由主 isolate 并发执行，结果按提交顺序返回。任务被取消或超时时，主 isolate 上未完成的请求 MUST 被中断。

#### Scenario: 取消时中断请求
- **WHEN** 任务在等待一个 10 秒后才响应的请求，此时任务被取消
- **THEN** 主 isolate 中断这个请求，提交方立即收到取消错误

#### Scenario: 整批并发
- **WHEN** 目录首页给出 5 个分页地址，每个分页响应耗时 1 秒
- **THEN** 5 个分页的总耗时小于 2 秒，章节顺序与分页顺序一致

### Requirement: 响应处理
系统 SHALL 自动跟随重定向，并把最终地址作为后续相对地址的基准。非 2xx 响应 MUST NOT 被当作错误，照常交给规则解析。连接超时为 15 秒，单次请求总超时为 60 秒。系统 SHALL 接受无效或自签名的 TLS 证书。

#### Scenario: 重定向后的相对地址
- **WHEN** 请求 `https://a.com/b?id=1` 被重定向到 `https://m.a.com/book/1/`，页面里的链接是 `2.html`
- **THEN** 链接解析为 `https://m.a.com/book/1/2.html`

#### Scenario: 404 照常解析
- **WHEN** 响应状态码是 404，body 是一个正常的 HTML 页面
- **THEN** 规则照常从这个页面取值

### Requirement: 响应解码
系统 SHALL 按以下顺序确定响应编码：去掉 UTF-8 BOM；使用响应头 Content-Type 里的 charset；使用 HTML `<meta>` 声明的 charset；以上都没有时，字节是合法 UTF-8 就按 UTF-8 解码，否则按 GBK 解码。URL 选项里的 `charset` MUST NOT 影响响应解码。编码名称无法识别时，系统 SHALL 按没有声明处理，不报错。

#### Scenario: meta 声明 GBK
- **WHEN** 响应头没有 charset，页面里有 `<meta charset="gbk">`
- **THEN** 按 GBK 解码，中文正确

#### Scenario: 没有任何声明的 GBK 页面
- **WHEN** 响应头和页面都没有声明编码，字节是 GBK 编码的中文
- **THEN** 按 GBK 解码，中文正确

### Requirement: 跨 worker 共享 Cookie
Cookie SHALL 只在主 isolate 上存一份，所有 worker 的请求共用，按注册域名（公共后缀加一级，IP 地址按原样）分组，只保存名和值。每个请求都 SHALL 带上书源地址所属域名下的 Cookie，与请求头里已有的 Cookie 合并时请求头优先。书源开启 `enabledCookieJar` 时，系统 SHALL 保存响应里的 Set-Cookie，并在每一跳重定向前按实际请求的域名再合并一次 Cookie，这次已保存的值优先。

#### Scenario: 登录态在 worker 之间共享
- **WHEN** 书源开启 `enabledCookieJar`，第一个请求在 worker A 上收到 `Set-Cookie: sid=1`，第二个请求在 worker B 上执行
- **THEN** 第二个请求带有 `sid=1`

#### Scenario: 子域名共享
- **WHEN** `www.a.com` 设置了 Cookie，随后请求 `m.a.com`
- **THEN** 请求带有这个 Cookie

#### Scenario: 公共后缀不合并
- **WHEN** `x.com.cn` 设置了 Cookie，随后请求 `y.com.cn`
- **THEN** 请求不带这个 Cookie

### Requirement: 书源限速
书源设置了 `concurrentRate` 时，系统 SHALL 按书源地址在所有 worker 之间统一限速：`N` 表示两次请求的发起间隔至少 N 毫秒；`a/b` 表示每 b 毫秒最多发起 a 次。为空、为 `0` 或无法解析时不限速。

#### Scenario: 间隔限速
- **WHEN** 书源 `concurrentRate` 是 `500`，两个 worker 同时请求这个书源
- **THEN** 两次请求的发起时间至少相隔 500 毫秒
