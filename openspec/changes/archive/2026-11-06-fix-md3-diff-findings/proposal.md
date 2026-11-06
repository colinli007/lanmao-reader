## Why

和 MD3 的差分测试（docs/review/MD3差分测试-2026-11-05.md）列出了我们和 MD3 不一致的问题。用户 2026-11-06 选定先修其中的第 3 到 6 条：都是引擎里具体的缺口，改动小。

动手前逐条查了根因：

- **第 6 条，关键词编码两次（我是盐神）**：引擎构造的地址是对的（`/categories/回答`）。服务器回 301，`Location` 头里是原始的 UTF-8 字节；`dart:io` 按 Latin-1 解码响应头，一个汉字变成三个字符，跟随重定向时再编码一次，成了 `%C3%A5%C2%9B…`。OkHttp 按 UTF-8 读响应头，MD3 没问题。
- **第 5 条，`res.raw().headers("Set-Cookie")[0]`（天籁小说）**：响应对象的 `headers` 忽略参数，总是返回整个响应头对象。OkHttp 的 `Response.headers(名)` 返回这个名字的全部值的列表。
- **第 4 条，`doc.getAllElements()` 和 `all.indexOf(el)`（白鹿书院）**：元素没有 `getAllElements`；`indexOf` 在 Rhino 里调的是 Java 列表的 `indexOf`，按 jsoup 的 `equals`（同一个节点）比较，我们的元素列表是 JS 数组，按 `===` 比，同一个节点每次交给 JS 都是新的包装对象，找不到。
- **第 3 条，POST 表单搜索（三三言情、三八小说）**：不是引擎问题。网站第一次请求时下发防火墙 Cookie（`waf_sc`）并返回错误页，带着 Cookie 的第二次才跳到结果页。MD3 保留了上一次对比留下的 Cookie；差分工具每次运行从空的 Cookie 开始。app 会保存 Cookie，第二次搜索就能搜到。这条从问题清单里去掉，在报告里说明。

## What Changes

- **响应头按 UTF-8 解码**：宿主执行请求时，响应头（包括跟随重定向用的 `Location`、交给规则的响应头和 `Set-Cookie`）按 UTF-8 重新解码，和 OkHttp 一致；不是合法 UTF-8 时保留原样。
- **`headers(名)`**：响应对象的 `headers` 带参数时，返回这个名字的全部值的列表（不区分大小写），`Set-Cookie` 每条一项；没有时是空列表。不带参数时照旧返回响应头对象。
- **元素**：
  - 元素加 `getAllElements()`：自己和全部后代元素，按文档顺序。
  - 元素列表的 `indexOf`、`lastIndexOf`、`includes`、`contains` 按「是不是同一个节点」比较，和 Rhino 调 Java 列表一样。
- **报告**：第 3 条改成「不是问题」，写明原因。

## Capabilities

### Modified Capabilities

- `source-request`：「响应处理」加响应头按 UTF-8 解码。
- `source-js-api`：「响应对象」加 `headers(名)`；「元素包装对象」加 `getAllElements()` 和列表按节点比较。

## Impact

- `packages/rule_engine/lib/src/host/rule_host.dart`：响应头解码。
- `packages/rule_engine/lib/src/js/prelude.dart`、`host_api.dart`：`headers(名)`、`getAllElements`、元素列表的比较。
- 测试：宿主的重定向测试（本地 HTTP 服务器返回 UTF-8 的 `Location`）、JS 测试；用差分工具复测这几个书源。
- `docs/review/MD3差分测试-2026-11-05.md`：第 3 条改为不是问题。
