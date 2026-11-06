## MODIFIED Requirements

### Requirement: 响应处理
系统 SHALL 自动跟随重定向，并把最终地址作为后续相对地址的基准。非 2xx 响应 MUST NOT 被当作错误，照常交给规则解析。连接超时为 15 秒，单次请求总超时为 60 秒。系统 SHALL 接受无效或自签名的 TLS 证书。

响应头 SHALL 按 UTF-8 解码（和 OkHttp 相同），包括跟随重定向用的 `Location`、交给规则的响应头和 `Set-Cookie`；不是合法 UTF-8 时保留原样。

#### Scenario: 重定向后的相对地址
- **WHEN** 请求 `https://a.com/b?id=1` 被重定向到 `https://m.a.com/book/1/`，页面里的链接是 `2.html`
- **THEN** 链接解析为 `https://m.a.com/book/1/2.html`

#### Scenario: 404 照常解析
- **WHEN** 响应状态码是 404，body 是一个正常的 HTML 页面
- **THEN** 规则照常从这个页面取值

#### Scenario: Location 里是中文
- **WHEN** 服务器返回 301，`Location` 头是 UTF-8 字节的 `/categories/回答/`
- **THEN** 跟随到 `/categories/%E5%9B%9E%E7%AD%94/`，最终地址里的中文按 UTF-8 编码一次
