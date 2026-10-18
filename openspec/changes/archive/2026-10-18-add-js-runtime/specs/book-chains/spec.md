## ADDED Requirements

### Requirement: 目录的 formatJs
目录规则有 `formatJs` 时，目录链路 SHALL 在得到全部章节后逐章执行它，注入 `gInt`（初始为 0）、`index`（从 1 开始的序号）、`chapter`、`title`，不注入 `java`、`source`、`book`，也不挂 jsLib；返回值不为 null 时转成文本作为章节名，为 null 时章节名不变。`formatJs` 的所有章节共用一个变量层，`gInt` 和未声明变量的修改在章节之间累积。某一章执行出错时 SHALL 只记录日志，这一章的章节名不变，其余章节照常处理。`preUpdateJs` 只在 MD3 更新书架书籍的目录时执行，不属于目录链路，本能力忽略它。

#### Scenario: 给章节加序号
- **WHEN** `formatJs` 是 `index + '. ' + title`，目录有「序章」「第一章」两章
- **THEN** 章节名依次为 `1. 序章`、`2. 第一章`

#### Scenario: 跨章节累积
- **WHEN** `formatJs` 是 `gInt++; gInt + title`，目录有三章
- **THEN** 三章的章节名分别以 `1`、`2`、`3` 开头

## MODIFIED Requirements

### Requirement: 链路在 worker 中执行
四条链路 SHALL 作为任务提交到工作 isolate 池执行，提交方异步拿到结果。输入和输出都 MUST 能在 isolate 之间传递。链路 SHALL 在每次请求之前和处理每一页之后检查取消，任务被取消或超时时尽快以对应错误结束。链路需要但本能力不支持的部分（不支持的宿主 API、WebView）以对应的错误结束；JS 出错时以 JS 错误结束；错误里带有书源名和出错的字段。

#### Scenario: 取消一次搜索
- **WHEN** 同一个取消令牌下有 20 个书源的搜索任务，令牌被触发
- **THEN** 20 个提交方都收到取消错误

#### Scenario: 错误指出字段
- **WHEN** 某书源的目录章节名规则是 `@js:java.getVerificationCode(result)`
- **THEN** 目录链路以「不支持的宿主 API」错误结束，错误里有书源名和 `ruleToc.chapterName`
