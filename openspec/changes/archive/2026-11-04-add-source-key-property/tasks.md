## 1. 引擎（packages/rule_engine）

- [x] 1.1 `source_js.dart` 的 `sourceFields` 加上 `key`、`tag`。验证：`source_js_api_test.dart`「键、名字、自定义变量」里加上 `source.key + source.tag` 和赋值被忽略。
- [x] 1.2 `prelude.dart` 给 URL 上下文的 `java` 定义 `url`、`ruleUrl` 读取器，`host_api.dart` 新增 `urlJava.url`、`urlJava.ruleUrl`。验证：`analyze_url_test.dart` 新增用例，选项 `js` 里读到当前地址和地址规则，赋值被忽略。
- [x] 1.3 `dart test`、`dart analyze`。验证：全部通过（901 个），没有问题。

## 2. 用真实书源验证

- [x] 2.1 用修改后的引擎对 yckceo 合集 1329（320 个书源）跑 `tool/smoke.dart`，搜索词 `doupo`，和修改前对比。验证：原来报「第 1 个参数不能为 null」的 9 个不再报这个错，结果记在这一项下面。

  结果（2026-11-03，macOS，`--concurrency 16`）：
  - 「第 1 个参数不能为 null」从 9 个降到 0 个。
  - 搜索成功 47 个（修改前 48 个）：多出来的书源现在都能发出请求了，但 `doupo` 是拼音，它们大多返回「搜索无结果」；网络类失败每次跑都有几个上下浮动。
  - 用 `斗破苍穹` 单独跑用到 `source.key` 的 25 个书源：8 个搜索成功，7 个四条链路全部通过。原来报 null 的 9 个里，米读小说、全本小说、第一站这 3 个现在全部通过；刚够小说网（用的是 `java.url`）能发出请求了，返回搜索无结果；其余几个分别卡在网站握手失败、网页改版后正则匹配不到。
- [x] 2.2 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-04）：用户确认后同步到主规格并归档。
