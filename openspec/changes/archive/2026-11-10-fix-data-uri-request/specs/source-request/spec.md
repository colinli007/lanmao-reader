## MODIFIED Requirements

### Requirement: URL 选项
地址后面的 `,{…}` SHALL 解析为请求选项，先按严格 JSON 解析，失败再按宽松语法（单引号、不带引号的键）解析，仍然失败时按没有选项处理。支持的选项：`method`（只认 POST、HEAD，其余按 GET）、`headers`（对象或 JSON 字符串，覆盖书源请求头）、`body`（字符串原样使用；对象或数组序列化为带缩进的 JSON）、`charset`（请求参数的编码）、`retry`（非 2xx 响应的重试次数，默认 0）、`type`（不为空时返回响应字节的十六进制字符串；这时地址（GET 请求去掉查询串）匹配 `data:…;base64,数据` 的，SHALL 不发请求，字节是数据按 Android `Base64.DEFAULT` 解码的结果，字母表以外的字符跳过，响应地址是请求地址）、`js`（地址转成绝对地址之后执行，`result` 是绝对地址，返回值不为 null 时作为新的地址；JS 里可以通过 `java.headerMap` 修改请求头）、`bodyJs`（拿到响应之后执行，`result` 是响应正文，返回值转成文本作为新的正文，null 转成字符串 `null`）。`webView` 为真（`null`、空串、`false`、`"false"` 以外的值，数字 0 也算真）时，MUST 以「需要 WebView」错误结束；`webJs` 只在使用 WebView 时生效，单独出现时忽略。

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

#### Scenario: type 选项的 data 地址
- **WHEN** 书籍地址是 `data:;base64,5LiJ5L2T,{"type":"qingtian"}`
- **THEN** 不发请求，详情规则拿到的正文是 `e4b889e4bd93`（`三体` 的 UTF-8 字节的十六进制）

#### Scenario: 不带 type 的 data 地址
- **WHEN** 书籍地址是 `data:;base64,5LiJ5L2T`，没有选项
- **THEN** 照常交给网络请求，以请求错误结束
