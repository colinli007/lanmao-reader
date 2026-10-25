## ADDED Requirements

### Requirement: 分段搜索
搜索 SHALL 可以分两段执行：
- 第一段构造搜索请求，交回提交方。地址规则里的 JS、书源请求头的 JS 在这一段执行。
- 提交方发出请求，把响应交给第二段。
- 第二段处理响应，得到结果。选项 `bodyJs`、`loginCheckJs`、列表规则在这一段执行。

两段 MAY 在不同的 worker 上执行，第一段交回的内容 MUST 能在 isolate 之间传递。

分两段执行时，每段里的 JS 只执行一次。结果、书源 JS 写的日志、书源级状态的读写、错误（包括书源名和字段）SHALL 和一次执行相同。请求失败时，这次搜索以网络错误结束，错误原因和一次执行时相同。

#### Scenario: 两段执行和一次执行结果相同
- **WHEN** 对同一个书源和同一份录制的搜索响应，分别一次执行、分两段在两个不同的 worker 上执行
- **THEN** 两次的结果相同

#### Scenario: 地址里的 JS 只执行一次
- **WHEN** 搜索地址是 `@js:java.log('构造');'/search?q='+key`，分两段执行
- **THEN** 书源日志里「构造」只有一条

#### Scenario: 第二段执行 loginCheckJs
- **WHEN** 书源的 `loginCheckJs` 是 `result.body().includes('请登录') ? java.getStrResponse() : result`，分两段执行，第一次响应正文含「请登录」，第二次不含
- **THEN** 第二段重新发出同一个搜索请求，结果按第二次的响应解析
