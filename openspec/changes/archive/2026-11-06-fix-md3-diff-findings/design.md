## Context

- `RuleHost._send` 用 `dart:io` 的 `HttpClient`，手动跟随重定向：`response.headers.value('location')`，`url.resolve(location)`。`dart:io` 把响应头的字节按 Latin-1 解码成字符串。
- OkHttp 用 `readUtf8LineStrict` 读响应头，按 UTF-8 解码（非法字节换成替换字符）。
- 元素交给 JS 时是句柄：`HandleTable.add` 对同一个节点返回同一个编号；JS 侧每次 revive 都新建 `JsElement`，元素列表是带隐藏方法的数组。
- 响应对象 `StrResponse` 的 `headers` 是「小写名 → 逗号连接的值」，另有 `setCookies` 保留每条 `Set-Cookie` 原文。

## Decisions

### D1 响应头在宿主里统一按 UTF-8 重新解码

为什么不在用 `Location` 的地方单独处理：交给规则的响应头、`Set-Cookie` 有同样的问题，统一在拿到响应时处理一次，和 OkHttp 的行为对应。

做法：一个值里所有字符都 ≤ 0xFF 且至少有一个 ≥ 0x80 时，把它当成 Latin-1 字节再按 UTF-8 解码；解码失败（不是合法 UTF-8）时保留原样。纯 ASCII 的值不动。

### D2 `headers(名)` 返回列表

和 OkHttp `Response.headers(name)` 一样，返回 `List<String>`。`Set-Cookie` 用 `setCookies`（每条一项）；其它响应头存的是逗号连接的值，返回只有一项的列表。没有这个头时是空列表。不带参数的 `headers()` 不变。

### D3 元素列表按节点比较，而不是缓存包装对象

两种做法：
- JS 侧按编号缓存 `JsElement`，让同一个节点总是同一个对象：`===` 也成立，但缓存要在合适的时候清掉，worker 一直活着，编号一直增长，清理的时机不好定。
- 元素列表的 `indexOf`、`lastIndexOf`、`includes`、`contains` 按句柄编号比较：这正是 Rhino 里的语义——书源调的是 Java 列表的方法，按 jsoup 的 `equals`（同一个节点）比；两个包装对象 `===` 在 Rhino 里也不成立。

选第二种：和 MD3 的语义完全对应，没有缓存。参数不是元素时按原来的数组方法处理。

### D4 getAllElements

jsoup 的 `Element.getAllElements()`：自己和全部后代元素，先序。文档对象也包括它自己（jsoup 的 `Document` 是 `Element`）。

## Risks / Trade-offs

- 极少数服务器的响应头真的是 Latin-1 文本（非 UTF-8）：解码失败时保留原样，和以前一样。
- `toArray()` 返回的是普通数组，上面的 `indexOf` 仍按 `===`；Rhino 里 `toArray()` 得到的是 Java 数组，书源很少在它上面用 `indexOf`。
