## ADDED Requirements

### Requirement: 正文图片
系统 SHALL 可以按书源取正文里的一张图片，在 worker 中执行，结果是图片的字节：

- 地址以 `data:` 开头时，按 base64 解码逗号后面的部分，不发请求。
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
