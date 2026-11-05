## ADDED Requirements

### Requirement: Jsoup
`org.jsoup.Jsoup.parse(html[, 基准地址])` SHALL 把 HTML 解析成文档，返回元素包装对象，上面的方法和「元素包装对象」相同，结果和规则引擎解析页面一致。`org.jsoup.Jsoup.parseBodyFragment(html)` SHALL 同样解析，内容放在 `body` 里。`Packages.org.jsoup.Jsoup` 是同一个对象。

给了基准地址时，这个文档里元素的 `attr('abs:属性')` SHALL 按基准地址把相对地址转成绝对地址，转不了时为空串；没有基准地址时只有本来就是绝对地址的能取到。

#### Scenario: 解析后选择
- **WHEN** 规则是 `@js:var doc = org.jsoup.Jsoup.parse(result); doc.select('a').first().text()`，`result` 是含 `<a>甲</a>` 的页面
- **THEN** 结果是 `甲`

#### Scenario: 基准地址
- **WHEN** 执行 `org.jsoup.Jsoup.parse('<a href="/b/1">x</a>', 'https://a.com/s').select('a').attr('abs:href')`
- **THEN** 结果是 `https://a.com/b/1`

### Requirement: WebView 的 User-Agent
`java.getWebViewUA()` 和 `source.getWebViewUA()` SHALL 返回一个固定的 Android WebView User-Agent（含 `; wv)`）。

#### Scenario: 取 UA
- **WHEN** 规则是 `@js:java.getWebViewUA()`
- **THEN** 结果包含 `; wv)` 和 `Mobile Safari`

## MODIFIED Requirements

### Requirement: 元素包装对象
HTML 元素交给 JS 时 SHALL 是包装对象，提供 jsoup 的常用方法：`text()`、`ownText()`、`html()`、`outerHtml()`、`data()`、`attr(名)`、`hasAttr(名)`、`hasClass(名)`、`id()`、`tagName()`、`select(CSS)`、`selectFirst(CSS)`、`children()`、`parent()`、`parentNode()`、`remove()`（从文档里删掉这个元素）。元素列表 SHALL 提供 `text()`、`html()`、`attr(名)`、`select(CSS)`、`eq(i)`、`first()`、`last()`、`get(i)`、`size()`、`isEmpty()`、`toArray()`、`remove()`（不带参数时从文档里删掉这些元素并返回列表本身；带下标时和 Java 列表一样从列表里删掉这一项并返回它），并且可以按下标和 `length` 访问。这些方法的结果 SHALL 与规则引擎里对应的 jsoup 语义一致。

#### Scenario: 列表转数组后取属性
- **WHEN** 页面有两个 `.d a`，执行 `java.getElements('.d a').toArray().map(a => a.text() + a.attr('href')).join(',')`
- **THEN** 结果是两个链接的文字和 href 依次拼接

#### Scenario: 删掉元素后取文本
- **WHEN** 文档是 `<div><p>甲</p><script>x</script></div>`，执行 `doc.select('script').remove(); doc.select('div').text()`
- **THEN** 结果是 `甲`

### Requirement: 不支持的宿主 API
下列 API 不在本能力内：界面交互（`startBrowser`、`startBrowserAwait`、`getVerificationCode`、`openUrl`）、WebView（`webView`、`webViewGetSource`、`webViewGetOverrideUrl`）、设备与 App 配置（`androidId`、`getReadBookConfig`、`getThemeMode`、`getThemeConfig`）、文件与压缩包（`downloadFile`、`cacheFile`、`importScript`、`getFile`、`readFile`、`readTxtFile`、`unzipFile` 等）、字体（`queryTTF`、`replaceFont`）、简繁转换（`t2s`、`s2t`）、非对称加密与签名（`createAsymmetricCrypto`、`createSign`）、需要重新拉取书籍的 `refreshTocUrl`、`reGetBook` 和发现页的 `refreshExplore`。调用它们时 MUST 以「不支持的宿主 API」错误结束，错误里带有 API 名、书源名和字段，MUST NOT 返回空值让书源继续执行。

#### Scenario: 调用验证码
- **WHEN** 正文规则执行 `java.getVerificationCode(url)`
- **THEN** 正文链路以「不支持的宿主 API：java.getVerificationCode」错误结束
