## MODIFIED Requirements

### Requirement: 响应对象
网络 API 返回的响应对象 SHALL 提供：`body()`（正文文本）、`code()` 和 `statusCode()`（状态码）、`message()`、`url()`（重定向后的最终地址）、`headers()`（响应头对象）、`headers(名)`（这个响应头的全部值的列表，不区分大小写，`Set-Cookie` 每条一项，没有时是空列表，和 OkHttp 的 `Response.headers(name)` 一样）、`header(名)`（单个响应头，不区分大小写）、`cookies()`（响应 Set-Cookie 的名值对象）、`isSuccessful()`，以及 `raw().request().url()`（最终地址）。

#### Scenario: 读响应头
- **WHEN** 响应头有 `Set-Cookie: sid=abc; Path=/`，执行 `java.head(url, {}).cookies().sid`
- **THEN** 结果为 `abc`

#### Scenario: 按名取全部值
- **WHEN** 响应有两条 `Set-Cookie`：`a=1; Path=/` 和 `b=2`，执行 `res.raw().headers("Set-Cookie")`
- **THEN** 结果是两项的列表，第一项是 `a=1; Path=/`

### Requirement: 元素包装对象
HTML 元素交给 JS 时 SHALL 是包装对象，提供 jsoup 的常用方法：`text()`、`ownText()`、`html()`、`outerHtml()`、`data()`、`attr(名)`、`hasAttr(名)`、`hasClass(名)`、`id()`、`tagName()`、`select(CSS)`、`selectFirst(CSS)`、`children()`、`parent()`、`parentNode()`、`getAllElements()`（自己和全部后代元素，按文档顺序）、`remove()`（从文档里删掉这个元素）。元素列表 SHALL 提供 `text()`、`html()`、`attr(名)`、`select(CSS)`、`eq(i)`、`first()`、`last()`、`get(i)`、`size()`、`isEmpty()`、`toArray()`、`remove()`（不带参数时从文档里删掉这些元素并返回列表本身；带下标时和 Java 列表一样从列表里删掉这一项并返回它），并且可以按下标和 `length` 访问。元素列表的 `indexOf`、`lastIndexOf`、`includes`、`contains` SHALL 按是不是同一个节点比较（Rhino 里调的是 Java 列表的方法），同一个节点分几次交给 JS 也算相同。这些方法的结果 SHALL 与规则引擎里对应的 jsoup 语义一致。

#### Scenario: 列表转数组后取属性
- **WHEN** 页面有两个 `.d a`，执行 `java.getElements('.d a').toArray().map(a => a.text() + a.attr('href')).join(',')`
- **THEN** 结果是两个链接的文字和 href 依次拼接

#### Scenario: 删掉元素后取文本
- **WHEN** 文档是 `<div><p>甲</p><script>x</script></div>`，执行 `doc.select('script').remove(); doc.select('div').text()`
- **THEN** 结果是 `甲`

#### Scenario: 按节点找位置
- **WHEN** 执行 `var all = doc.getAllElements(); all.indexOf(doc.select('p').first())`，文档里第一个 `p` 是 `body` 的第一个子元素
- **THEN** 结果是 `p` 在全部元素里的位置，不是 -1
