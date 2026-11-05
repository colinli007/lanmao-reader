## MODIFIED Requirements

### Requirement: Rhino 专有写法
书源 JS 执行之前，`=>` 前面紧挨着的数组字面量（`[a,b]=>`，Rhino 当成解构参数）SHALL 被加上括号（`([a,b])=>`）再执行；字符串、模板字符串、注释和正则字面量里的内容 MUST NOT 被改动，下标访问（`a[0]`）MUST NOT 被当成解构参数。

全局的 `org` 和 `Packages` SHALL 是 Java 包对象：`org.jsoup.Jsoup`、`org.jsoup.parser`（以及 `Packages.org.jsoup…`）按 source-js-api「Jsoup」提供；调用或 `new` 其它任何类时 MUST 以「不支持的宿主 API：类名」结束，JS 的 try/catch 拦不住。`org`、`Packages` 在 jsLib 的代码里（顶层和函数里）和变量层的 `this` 上 SHALL 同样可用。其余依赖 Rhino Java 互操作的写法（`JavaImporter`、`importPackage`、`java.lang.*`、Java 字符串方法如 `.length()`、`.equals()`）不在支持范围，MUST 以错误结束，MUST NOT 被静默改写成别的语义。宿主 API 返回的字符串 SHALL 是 JS 原生字符串（MD3 里是 Java 字符串对象），`===` 比较和 `replaceAll` 按 JS 语义。

#### Scenario: 解构箭头函数
- **WHEN** 规则是 `@js:[["男频","1"],["女频","2"]].map([t,id]=>t+id).join(",")`
- **THEN** 结果是 `男频1,女频2`

#### Scenario: 字符串里的不改
- **WHEN** 规则是 `@js:"[a]=>" + [1][0]`
- **THEN** 结果是 `[a]=>1`

#### Scenario: jsLib 里用 Jsoup
- **WHEN** jsLib 是 `function first(h) { const { Packages } = this; return Packages.org.jsoup.Jsoup.parse(h).select("p").first().text(); }`，规则求值 `first("<p>甲</p>")`
- **THEN** 结果是 `甲`

#### Scenario: 使用 Packages
- **WHEN** 规则是 `@js:Packages.java.lang.System.currentTimeMillis()`
- **THEN** 以「不支持的宿主 API：Packages.java.lang.System.currentTimeMillis」错误结束
