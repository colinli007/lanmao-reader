# source-js-api Specification

## Purpose

注入书源 JS 的宿主 API：`java`、`cookie`、`cache`、`source`、`book`、`chapter` 上的方法。语义以 legado-with-MD3（commit `d1b488b`）为准，包括它的怪异行为；依赖界面、WebView 或设备的 API 不在本能力内，以明确的错误结束。

## Requirements

### Requirement: 三种 java 对象
`java` SHALL 按进入点区分：规则里的 JS 拿到规则上下文对象，URL 里的 JS 和 `loginCheckJs` 拿到 URL 上下文对象，书源 `header` 的 JS 拿到书源对象。编码、摘要与加解密、时间、文本、日志和网络方法三种对象都有；回调规则方法（`getString`、`getStringList`、`getElement`、`getElements`、`setContent`）只在规则上下文；`getStrResponse`、`initUrl`、`headerMap` 只在 URL 上下文。URL 上下文对象还 SHALL 有只读属性 `url`（当前请求的地址）和 `ruleUrl`（替换过 `{{}}`、还带着选项的地址规则），对应 MD3 `AnalyzeUrl` 的公开属性，每次读取时取当前值，赋值被忽略。调用当前对象上没有的方法 MUST 以 JS 错误结束。

#### Scenario: URL 里调用回调规则
- **WHEN** 搜索地址里执行 `java.getString('tag.a@text')`
- **THEN** 以 JS 错误结束

#### Scenario: 选项 js 里读当前地址
- **WHEN** 书源地址是 `https://a.com`，搜索地址是 `/s?q={{key}},{"js":"java.url + '#u'"}`，关键词是 `k`
- **THEN** 请求的地址是 `https://a.com/s?q=k#u`

### Requirement: 变量读写
规则上下文的 `java.put(键, 值)` SHALL 只写入第一个存在的对象：当前章节、当前书籍（搜索列表阶段是当前结果项）、本次链路的变量；三者都不存在时写入书源级变量。`java.get(键)` SHALL 按同样的顺序返回第一个非空值，都没有时返回空串；`bookName` 和 `title` 分别返回书名和章节名。规则里的 `@put`、`@get` 与 `java.put`、`java.get` 读写同一份数据。URL 上下文的 `put` SHALL 只写当前章节或本次链路的变量，两者都没有时丢弃；`get` 不读书源级变量。书源对象（书源 `header` 的 JS）上的 `put`、`get` 读写书源级变量。`java.put` 返回写入的值。`java.put` 的值是 null 时 MUST 以 JS 错误结束。

#### Scenario: JS 写、规则读
- **WHEN** 详情的 init 规则执行 `java.put('bid', '9')`，目录地址规则是 `/toc/@get:{bid}`
- **THEN** 目录请求地址是 `/toc/9`

#### Scenario: URL 里写变量后在列表里读
- **WHEN** 搜索地址里执行 `java.put('t', 'x')`，搜索结果项的书名规则是 `@get:{t}`
- **THEN** 每一项的书名为 `x`

### Requirement: ajax 与 ajaxAll
`java.ajax(地址)` SHALL 按 URL 规则（支持 `,{选项}`、`@js:`、`{{}}`）构造请求，带上书源请求头、登录头和按书源地址（而不是请求地址）的域名取出的 Cookie，同步返回响应正文。相对地址 MUST NOT 被补全。地址是数组时只用第一个元素。`type` 选项不为空时返回响应字节的十六进制字符串。非 2xx 响应 SHALL 返回响应正文；网络错误 MUST NOT 抛出 JS 异常，而是返回错误的描述文本。`java.ajaxAll(地址数组)` SHALL 并发请求，按输入顺序返回响应对象数组，任一请求出错时以 JS 错误结束。任务被取消时，阻塞中的 `ajax` 和 `ajaxAll` MUST 让 JS 中止。

#### Scenario: 请求失败不抛异常
- **WHEN** 执行 `java.ajax('http://127.0.0.1:1/x')`，端口不可连接
- **THEN** 返回一段描述连接失败的文本，JS 继续执行

#### Scenario: 带书源 Cookie
- **WHEN** 书源地址是 `https://www.a.com`，Cookie 存储里 `a.com` 有 `sid=1`，执行 `java.ajax('https://api.b.com/x')`
- **THEN** 请求头的 Cookie 含 `sid=1`

### Requirement: connect 与直连请求
`java.connect(地址[, 请求头 JSON[, 超时]])` SHALL 像 `ajax` 一样请求，返回响应对象；请求头参数是合法 JSON 时整体替换书源请求头和登录头。出错时 MUST NOT 抛出，返回一个状态码为 200、正文为错误描述的响应对象。`java.get(地址, 请求头)`、`java.post(地址, 正文, 请求头)`、`java.head(地址, 请求头)` SHALL 直接请求：不解析 URL 选项，不带书源请求头、登录头和 Cookie，不跟随重定向，默认超时 30 秒；状态码大于等于 400 时 MUST 以 JS 错误结束。

#### Scenario: 拿到重定向地址
- **WHEN** 服务器对 `/go` 返回 302、`Location: /book/1`，执行 `java.get(url, {}).header('Location')`
- **THEN** 结果为 `/book/1`

### Requirement: 响应对象
网络 API 返回的响应对象 SHALL 提供：`body()`（正文文本）、`code()` 和 `statusCode()`（状态码）、`message()`、`url()`（重定向后的最终地址）、`headers()`（响应头对象）、`headers(名)`（这个响应头的全部值的列表，不区分大小写，`Set-Cookie` 每条一项，没有时是空列表，和 OkHttp 的 `Response.headers(name)` 一样）、`header(名)`（单个响应头，不区分大小写）、`cookies()`（响应 Set-Cookie 的名值对象）、`isSuccessful()`，以及 `raw().request().url()`（最终地址）。

#### Scenario: 读响应头
- **WHEN** 响应头有 `Set-Cookie: sid=abc; Path=/`，执行 `java.head(url, {}).cookies().sid`
- **THEN** 结果为 `abc`

#### Scenario: 按名取全部值
- **WHEN** 响应有两条 `Set-Cookie`：`a=1; Path=/` 和 `b=2`，执行 `res.raw().headers("Set-Cookie")`
- **THEN** 结果是两项的列表，第一项是 `a=1; Path=/`

### Requirement: 回调规则
规则上下文的 `java.getString(规则[, 内容[, 是否地址]])` SHALL 用完整的规则语法（含 JS）求值；不传内容时使用当前内容（当前结果项或页面），而不是 `result`。`getStringList` 规则为空或取不到时返回 null。`getElements` SHALL 返回元素包装对象列表，取不到时为空列表；`getElement` 在 JSoup、CSS、XPath 规则下同样返回列表（与 MD3 一致）。`java.setContent(内容[, 基准地址])` SHALL 替换当前上下文的内容，后续字段规则在新内容上取值；内容为 null 时 MUST 以 JS 错误结束。

#### Scenario: 回调用的是当前内容
- **WHEN** 结果项是 `<li><a href="/b/1">三体</a><i>刘慈欣</i></li>`，作者规则是 `tag.i@text@js:java.getString('tag.a@text') + '/' + result`
- **THEN** 作者为 `三体/刘慈欣`

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

### Requirement: 编码
SHALL 提供：`base64Decode(文本[, 字符集])`（宽松：忽略空白、容忍缺少 `=` 和 URL 安全字符，空值返回空串）、`base64Decode(文本, flags)` 和 `base64DecodeToByteArray(文本[, flags])`（严格，按 Android Base64 的 flags；非法输入以 JS 错误结束；`base64DecodeToByteArray` 对空白输入返回 null）、`base64Encode(文本[, flags])`（默认 NO_WRAP）、`hexDecodeToString`、`hexDecodeToByteArray`、`hexEncodeToString`（小写）、`strToBytes(文本[, 字符集])`、`bytesToStr(字节[, 字符集])`、`encodeURI(文本[, 字符集])`（表单编码，空格为 `+`）。字节数组在 JS 里 SHALL 是取值 -128 到 127 的数字数组（与 Java `byte[]` 一致），作为参数时也接受这种数组。字符集支持 UTF-8、GBK、GB2312、GB18030 和 ISO-8859-1。

#### Scenario: 宽松 Base64
- **WHEN** 执行 `java.base64Decode('5LiJ5L2T\n')`
- **THEN** 结果为 `三体`

#### Scenario: encodeURI 是表单编码
- **WHEN** 执行 `java.encodeURI('a b+三')`
- **THEN** 结果为 `a+b%2B%E4%B8%89`

### Requirement: 摘要与加解密
SHALL 提供：`md5Encode`（32 位小写）、`md5Encode16`（32 位结果的第 9 到 24 位）、`digestHex(数据, 算法)` 和 `digestBase64Str`（MD5、SHA-1、SHA-224、SHA-256、SHA-384、SHA-512）、`HMacHex(数据, 算法, 密钥)` 和 `HMacBase64`（HmacMD5、HmacSHA1、HmacSHA256、HmacSHA512，算法名不区分大小写），文本按 UTF-8。`createSymmetricCrypto(变换[, 密钥[, IV]])` SHALL 支持 AES、DES、DESede，ECB、CBC 模式，PKCS5Padding（PKCS7Padding 视同）和 NoPadding；变换里只有算法名时按 `算法/ECB/PKCS5Padding`；密钥和 IV 可以是文本（UTF-8）或字节数组；DES 密钥超过 8 字节截到 8，DESede 超过 24 字节截到 24，AES 密钥长度不是 16、24、32 时在第一次加解密时以 JS 错误结束；ECB 模式忽略 IV。返回对象 SHALL 提供 `encrypt`、`encryptBase64`、`encryptHex`、`encryptStr`、`decrypt`、`decryptStr`、`decryptHex`、`decryptBase64`、`setIv`；`decrypt`、`decryptStr` 收到文本时，全是十六进制字符且长度为偶数则按十六进制解析，否则按宽松 Base64 解析。旧版便捷函数（`aesDecodeToString`、`aesBase64DecodeToString`、`aesEncodeToBase64String`、`aesDecodeArgsBase64Str`、`desDecodeToString`、`desEncodeToBase64String`、`tripleDESDecodeStr` 等）SHALL 照 MD3 的实际行为实现，包括 `aesEncodeToString` 实际做解密、`aesEncodeArgsBase64Str` 不对密钥和 IV 做 Base64 解码。加解密出错（填充错误、密钥长度不对、格式不对）MUST 以 JS 错误结束。

#### Scenario: AES 默认 ECB
- **WHEN** 执行 `java.createSymmetricCrypto('AES', '1234567890123456').encryptBase64('三体')`
- **THEN** 结果与 JDK `AES/ECB/PKCS5Padding` 用同样密钥加密 UTF-8 `三体` 后的标准 Base64 相同

#### Scenario: 旧函数的 bug 照旧
- **WHEN** 用 `aesEncodeToString` 处理一段 AES 密文
- **THEN** 得到的是解密后的明文

### Requirement: 时间与文本
`java.timeFormat(毫秒)` SHALL 按设备本地时区输出 `yyyy/MM/dd HH:mm`；`java.timeFormatUTC(毫秒, 格式, 偏移)` SHALL 以偏移（单位是毫秒）为时区，按 Java `SimpleDateFormat` 的格式语法输出（支持 `y M d H h m s S E a Z` 等常用字母和单引号转义）。`java.toNumChapter(文本)` SHALL 找第一个 `第…章`，把中间的中文或全角数字转成阿拉伯数字，只返回 `第N章`（前后文字丢掉）；没有匹配时原样返回；中间部分无法解析时得到 `第-1章`。`java.htmlFormat(文本)` 与正文格式化（保留图片）一致。`java.randomUUID()` 返回小写带连字符的 v4 UUID。

#### Scenario: UTC 偏移按毫秒
- **WHEN** 执行 `java.timeFormatUTC(0, 'yyyy-MM-dd HH:mm', 28800000)`
- **THEN** 结果为 `1970-01-01 08:00`

#### Scenario: 中文章节号
- **WHEN** 执行 `java.toNumChapter('正文 第一百零五章 风起')`
- **THEN** 结果为 `第105章`

### Requirement: 日志与提示
`java.log(值)` SHALL 把值转成文本写入书源调试日志，并原样返回该值；`java.logType(值)` 写入值的类型名。`java.toast(文本)`、`java.longToast(文本)` SHALL 降级为写日志，不报错。调试日志 SHALL 在写入时就交给主 isolate 上的日志接收方，带上书源地址和所在字段，调用方可以实时显示。

#### Scenario: log 可以写在表达式里
- **WHEN** 规则是 `@js:java.log(result.length)`，`result` 是 `abc`
- **THEN** 结果为 `3`，日志接收方收到一条带书源地址的 `3`

### Requirement: Cookie
`cookie.getCookie(地址)`、`cookie.getKey(地址, 名)`、`cookie.setCookie(地址, 文本)`（覆盖）、`cookie.replaceCookie(地址, 文本)`（按名合并）、`cookie.removeCookie(地址)`、`cookie.cookieToMap(文本)`、`cookie.mapToCookie(对象)` 和 `java.getCookie(地址[, 名])` SHALL 读写与网络请求相同的 Cookie 存储：地址以 `http://` 或 `https://` 开头时按 eTLD+1 归一，否则把整个文本当作键。`cookieToMap` 丢弃值为空的项，`mapToCookie` 用 `; ` 连接。

#### Scenario: JS 清掉 Cookie 后请求不再带
- **WHEN** 执行 `cookie.removeCookie('https://www.a.com')`，之后书源请求 `https://m.a.com/x`
- **THEN** 请求不带 `a.com` 的 Cookie

### Requirement: 缓存
`cache.put(键, 值[, 保存秒数])` SHALL 以文本保存值（对象按 JS 的 `String()` 转成文本，数字按「值转换」里的数字格式），保存秒数为 0 或缺省时不过期；`cache.get(键)` 返回未过期的值，没有时返回 null；`cache.delete(键)` 删除。`cache.putFile`、`cache.getFile` 与 `put`、`get` 共用同一份存储，`cache.putMemory`、`cache.getFromMemory`、`cache.deleteMemory` 只在内存里。缓存 SHALL 在同一进程的所有 worker 之间共享；本能力只提供进程内的存储，不负责落盘。

#### Scenario: 不同 worker 读到同一份缓存
- **WHEN** 一个任务执行 `cache.put('k', 'v')`，之后另一个 worker 上的任务执行 `cache.get('k')`
- **THEN** 结果为 `v`

### Requirement: 书源对象的方法
`source.getKey()` SHALL 返回书源地址，`source.getTag()` 返回书源名。`source.getVariable()`、`source.setVariable(文本)`（`putVariable` 同义，null 为删除）读写书源自定义变量。`source.getLoginHeader()`、`source.getLoginHeaderMap()`、`source.putLoginHeader(JSON 文本)`、`source.removeLoginHeader()` 读写登录头：`putLoginHeader` 的 JSON 里有 `Cookie` 或 `cookie` 时按名合并进书源域名的 Cookie；登录头 SHALL 叠加到该书源之后的请求头里。`source.getLoginInfo()`、`source.getLoginInfoMap()`、`source.putLoginInfo(文本)`、`source.removeLoginInfo()` 读写登录信息；没有保存的登录信息、`loginUi` 是 JSON 时，`getLoginInfoMap` 返回其中非按钮项的 `name` 到 `default`（缺省为空串）的映射。这些书源级数据 SHALL 在同一进程的所有 worker 之间共享。

#### Scenario: 登录头生效
- **WHEN** 书源 JS 执行 `source.putLoginHeader('{"Authorization":"Bearer t"}')`，之后该书源发出请求
- **THEN** 请求头带有 `Authorization: Bearer t`

### Requirement: 书籍和章节的方法
`book.getVariable(键)`、`book.putVariable(键, 值)`、`chapter.getVariable(键)`、`chapter.putVariable(键, 值)` SHALL 读写对应对象的变量（值为 null 时删除），变量随链路结果返回。`book.setReverseToc(布尔)` SHALL 设置目录是否倒序，在目录规则里调用时影响本次目录的顺序。`book.upCustomIntro()` SHALL 把当前简介设为自定义简介。

#### Scenario: 章节变量传到正文
- **WHEN** 目录项规则执行 `chapter.putVariable('cid', '42')`，正文规则里执行 `java.get('cid')`
- **THEN** 结果为 `42`

### Requirement: 不支持的宿主 API
下列 API 不在本能力内：界面交互（`startBrowser`、`startBrowserAwait`、`getVerificationCode`、`openUrl`）、WebView（`webView`、`webViewGetSource`、`webViewGetOverrideUrl`）、设备与 App 配置（`androidId`、`getReadBookConfig`、`getThemeMode`、`getThemeConfig`）、文件与压缩包（`downloadFile`、`cacheFile`、`importScript`、`getFile`、`readFile`、`readTxtFile`、`unzipFile` 等）、字体（`queryTTF`、`replaceFont`）、简繁转换（`t2s`、`s2t`）、非对称加密与签名（`createAsymmetricCrypto`、`createSign`）、需要重新拉取书籍的 `refreshTocUrl`、`reGetBook` 和发现页的 `refreshExplore`。调用它们时 MUST 以「不支持的宿主 API」错误结束，错误里带有 API 名、书源名和字段，MUST NOT 返回空值让书源继续执行。

#### Scenario: 调用验证码
- **WHEN** 正文规则执行 `java.getVerificationCode(url)`
- **THEN** 正文链路以「不支持的宿主 API：java.getVerificationCode」错误结束

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
