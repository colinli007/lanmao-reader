## MODIFIED Requirements

### Requirement: 三种 java 对象
`java` SHALL 按进入点区分：规则里的 JS 拿到规则上下文对象，URL 里的 JS 和 `loginCheckJs` 拿到 URL 上下文对象，书源 `header` 的 JS 拿到书源对象。编码、摘要与加解密、时间、文本、日志和网络方法三种对象都有；回调规则方法（`getString`、`getStringList`、`getElement`、`getElements`、`setContent`）只在规则上下文；`getStrResponse`、`initUrl`、`headerMap` 只在 URL 上下文。URL 上下文对象还 SHALL 有只读属性 `url`（当前请求的地址）和 `ruleUrl`（替换过 `{{}}`、还带着选项的地址规则），对应 MD3 `AnalyzeUrl` 的公开属性，每次读取时取当前值，赋值被忽略。调用当前对象上没有的方法 MUST 以 JS 错误结束。

#### Scenario: URL 里调用回调规则
- **WHEN** 搜索地址里执行 `java.getString('tag.a@text')`
- **THEN** 以 JS 错误结束

#### Scenario: 选项 js 里读当前地址
- **WHEN** 书源地址是 `https://a.com`，搜索地址是 `/s?q={{key}},{"js":"java.url + '#u'"}`，关键词是 `k`
- **THEN** 请求的地址是 `https://a.com/s?q=k#u`
