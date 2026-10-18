## ADDED Requirements

### Requirement: 需要 WebView 时明确报错
规则里出现 `@webjs:` 时，系统 SHALL 以「需要 WebView」错误结束，错误里带有出错的规则片段。系统 MUST NOT 跳过这个片段继续求值。

#### Scenario: 规则里有 @webjs:
- **WHEN** 正文规则是 `@webjs:document.body.innerText`
- **THEN** 以「需要 WebView」错误结束，错误里带有 `@webjs:document.body.innerText`

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: 需要 JS 时明确报错
**Reason**: 规则里的 `@js:`、`<js>…</js>` 和 `{{表达式}}` 改为由 JS 运行时执行，不再报错。
**Migration**: 执行语义见 source-js 的「规则里的 JS 段」「值转换」；`@webjs:` 的报错移到本能力新增的「需要 WebView 时明确报错」；调用不支持的宿主 API 的报错见 source-js-api 的「不支持的宿主 API」。
