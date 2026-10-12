# MD3 请求构造与四条链路语义清单

来源：legado-with-MD3 commit `d1b488b`，`app/src/main/java/io/legado/app/` 下的源码。2026-10-11 提取，供 Dart 实现逐条对照。

这份清单基于只读源码整理，基线是 legado-with-MD3 的 d1b488b。下文路径省略前缀 `app/src/main/java/io/legado/app/`，「JS」表示 Dart 版需要留接口的接入点。

## 1. URL 模板（AnalyzeUrl）

- **处理顺序**（AnalyzeUrl.kt:148-156）：
  1. 先处理 `@js:` 和 `<js>…</js>`（AppPattern.kt:5-6）。整条 URL 会被 JS 结果替换，前面的文字作为 `result` 传入，文字里的 `@result` 也会被替换（:161-183）。这是 JS 接入点。
  2. 再处理 `{{…}}`。
  3. 然后处理 `<a,b,c>` 页码。
  4. 最后切出 `,{选项}`。
- **`{{…}}` 一律当 JS 执行**（:190-202），`{{key}}`、`{{page}}` 也一样。可用的绑定有 key、page、baseUrl、book、source、java、cookie 等（:363-377）。取值规则：
  - 结果是整数形式的 Double，按 `%.0f` 输出。
  - 结果为 null 时输出 `""`。
  - 解析不考虑嵌套，取第一个 `{{` 到下一个 `}}` 之间的内容（RuleAnalyzer.kt:339-365）。
  - A 类书源至少要在 Dart 里实现 `key`、`page` 和整数算术，其余转交 JS。
  - 关键字原样插入，这一步不编码。
- **页码语法 `<…>`**：只在 `page != null` 时生效（只有搜索和发现会传 page）。URL 里所有 `<(.*?)>` 都按逗号拆开，取值规则如下（:204-213）：
  - `page < 数量` 时取 `pages[page-1]`，否则取最后一个。
  - 两端用 `<=' '` 规则 trim。
  - `page=0` 会越界抛错。
- **选项切分**：`\s*,\s*(?=\{)` 的第一个匹配处（:776）。JSON 先按严格模式解析，失败再按宽松模式（:230-236）。解析失败时不报错，按没有选项处理。
- **相对地址**：URL 先对传入的 baseUrl 求绝对地址，baseUrl 已去掉选项部分（:130-131、:224）。
  - `NetworkUtils.getAbsoluteURL` 会把 base 从**第一个逗号**处截断（NetworkUtils.kt:170）。
  - 以 `javascript` 开头的地址返回 `""`，`data:` 地址原样返回（:183-185）。
  - 之后成员 baseUrl 被改成只剩 scheme+host（:225-227），只给 JS 用。
- **UrlOption 字段**（:812-988）：
  - `method`：不区分大小写。POST、HEAD 以外一律按 GET。
  - `headers`：可以是对象，也可以是 JSON 字符串。会覆盖书源 header。
  - `body`：字符串原样使用；对象或数组用 GSON 序列化，而这个 GSON **开了 PrettyPrinting**，所以请求体是带换行和缩进的 JSON（GsonExtensions.kt:38）。整数保持整数（LONG_OR_DOUBLE）。
  - `charset`：只影响**请求参数的编码**（见第 3 节）。
  - `retry`：默认 0。字符串 `"3"` 会被 IntJsonDeserializer 解析成 null，等于 0（GsonExtensions.kt:144-165）。
  - `type`：不为 null 时直接取字节，返回十六进制字符串（:420-422）。
  - `webView`：只有 `null`、`""`、`false`、`"false"` 算 false，**数字 0 算 true**（:900-905）。
  - `origin`：会解析，但这条链路**没用到**。
  - 以下字段都是 JS 或 WebView 接入点：`js`（以 url 为 result 执行，结果覆盖 url，:258-262）、`bodyJs`、`webJs`、`webViewDelayTime`、`dnsIp`、`serverID`。
- **GET 编码**（:268-275、:301-313、:785-801）：
  - 从 `?` 后取整个 query。如果它已经是合法编码（只含安全字符和合法 `%XX`，NetworkUtils.kt:75、:104-128），原样使用。
  - 否则逐字符处理：安全集 `A-Za-z0-9_.-~!$%&()*+,/:;=?@[\]^\`{|}` 内的字符保留，其余按 charset（默认 UTF-8，如 `gbk`）转字节再输出 `%XX` 大写。空格变成 `%20`，`+` 保留不动。
  - `charset:"escape"` 时按 `&`、`=` 拆开，逐项做 JS 风格的 escape：小写十六进制，`%uXXXX`（EncoderUtils.kt:11-28）。
  - 最后交给 OkHttp 的 `encodedQuery`（OkHttpUtils.kt:131-135）。
- **POST 请求体**（:277-281、:477-489）：
  - body 不像 JSON、也不像 XML（判断只看首尾字符），且没有 Content-Type 头时，按 form 编码：
    - 用 `URLEncoder.encode(charset)`，空格变成 `+`。
    - 只有**没指定 charset** 时，才跳过已经编码过的值（NetworkUtils.kt:92）。指定了 GBK 时，已编码的值会被**二次编码**。
  - 发送时按以下顺序选一种：
    - encodedForm 非空，或 body 为空白：发 `application/x-www-form-urlencoded`。
    - 有 Content-Type 头：原样发 body，使用该类型。
    - 其余情况：发 `application/json; charset=UTF-8`。所以**没有 Content-Type 的 XML body 会按 JSON 发出**。
  - POST 时 url 里的 query 保留，不再编码。
- **HEAD 会丢掉 query**：`get(urlNoQuery=url, null)` 会把 query 清空（:491-494）。

## 2. 请求头、Cookie、限速

- **header 合成**（BaseSource.kt:102-131）：
  - 书源 `header` 以 `@js:` 或 `<js>` 开头（不区分大小写）时走 JS（接入点）。
  - 内容先按严格 JSON 解析，失败再按宽松解析；出错只记日志。
  - 没有 UA 时（不区分大小写）补上默认 UA。
  - 再叠加登录头 `loginHeader_<书源URL>`。
  - header 里的 `proxy` 键会被取出，作为代理配置（AnalyzeUrl.kt:136-139，格式见 HttpHelper.kt:203）。
- **默认 UA**：`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/<cronet版本> Safari/537.36`（FeatureSettingsRepositories.kt:158-162）。
- **请求拦截器**会做这些事（HttpHelper.kt:96-107）：
  - 没有 UA 时补默认值；UA 的值是字面量 `"null"` 时删掉 UA。
  - 一律加上 `Keep-Alive: 300` 和 `Connection: Keep-Alive`。
  - 没有 Accept-Encoding 和 Range 时，加 `gzip, deflate`。deflate 按 raw 方式解（nowrap，DecompressInterceptor.kt:20-37）。
- **客户端行为**：TLS 不校验证书、自动跟随重定向（:89-94），有 100MB 的 HTTP 缓存（:80-83）。
- **Cookie 的键是 eTLD+1**（`getSubDomain` 用 PublicSuffix 计算；IP 原样返回，NetworkUtils.kt:217-228）。
  - **每个请求**都会附上 `CookieStore.getCookie(书源URL的域)`。这和 enabledCookieJar 无关，取的也不是请求 URL 的域（AnalyzeUrl.kt:142、:706-722）。
  - 和请求头里已有的 Cookie 合并时，**请求头的值优先**。
  - 存储内容 = 数据库里的持久 cookie + 内存里的会话 cookie。总长度超过 4096 时随机删掉若干个键（CookieStore.kt:54-70）。
- **enabledCookieJar=true 时**，通过内部头 `CookieJar:1` 标记，由网络拦截器处理，这个内部头不能发到网络上（HttpHelper.kt:109-125）。
  - **每一跳重定向**都会按**实际请求 URL 的域**再合并一次 Cookie，这次**存储的值优先**（CookieManager.kt:55-75）。
  - 响应的 Set-Cookie 只保留 name=value：持久 cookie 按名合并写入数据库，会话 cookie 写进内存（CookieManager.kt:41-50、CookieStore.kt:36-49）。
  - path、过期时间都被忽略；值为空白的 cookie 直接丢掉，所以「删除 cookie」不会生效（CookieStore.kt:87-105）。
  - `saveCookie()` 从未被调用（AnalyzeUrl.kt:733）。
  - 字段默认值：构造器默认 true，数据库列默认 0（BookSource.kt:58-59）。
- **concurrentRate 不是并发数**（ConcurrentRateLimiter.kt:58-105）：
  - 用书源 URL 作键，全局共享。按**请求发起时刻**计数，请求结束时不释放。
  - `"N"`：两次请求的发起间隔至少 N 毫秒。
  - `"a/b"`：从窗口内第一次请求起算，每 b 毫秒最多 a 次，超出就 sleep 等到窗口结束。
  - 空值或 `"0"` 不限速；解析失败时间隔取 0。

## 3. 响应

- **非 2xx 不报错**，照常解析 body。`retry` 只在非 2xx 时重试，IO 异常不重试，重试用完后返回最后一次响应（OkHttpUtils.kt:29-43）。
- **超时**：连接 15s、写 15s、读 60s、整个调用 60s（HttpHelper.kt:84-87）。
- **解码**（OkHttpUtils.kt:79-95）：
  1. 先去掉 UTF-8 BOM。
  2. 有响应头 charset 就用它。
  3. 否则探测 meta，再不行用 ICU 自动检测（EncodingDetect.kt:14-52）。
  - **urlOption 里的 charset 不参与响应解码**（:56-58 调 `text()` 时没传 encode 参数）。
  - meta 探测只认字面量 `<head>`；写成 `<head lang=..>` 时退回 ICU 检测。
  - `http-equiv` 的 content 里没有 `charset=` 时，会把整个 content（比如 `text/html`）当编码名，`Charset.forName` **直接抛错**。建议 Dart 版改成容错，并把这处偏离记下来。
- **XML 补声明**：Content-Type 匹配 `(application|text)/\w*\+?xml.*`，且 body 不以 `<?xml` 开头时，在前面补 `<?xml version="1.0"?>`。这里是 else-if 结构，**补了声明就不再执行 bodyJs**（AnalyzeUrl.kt:498-507）。
- **重定向**：`res.url` 取 `networkResponse.request.url`，也就是最终地址（StrResponse.kt:56-61）。
  - 规则里 `isUrl` 的相对地址按 **redirectUrl** 解析（AnalyzeRule.kt:271-282、:367-374）。
  - 规则非空但取到空白时，返回 `baseUrl`；规则本身为空时返回 `""`（:292、:368-369）。
  - Java `URL(base, rel)` 的相对解析和 Dart `Uri.resolve` 可能不一致（比如 `?q`、`../` 的处理），需要对照测试。

## 4. 搜索（WebBook.kt:50-90，BookList.kt）

- searchUrl 为空时抛「搜索url不能为空」。page 默认 1。
- 每个响应先过一遍 `loginCheckJs`（JS 接入点，WebBook 里 5 处）。
- **按详情页处理的判定**：
  - 搜索时，如果 `bookUrlPattern` 对 res.url **整串匹配**（Kotlin `matches`，BookList.kt:62-80），整页按详情页解析后直接返回。
  - 列表为空且 bookUrlPattern 为空时，也按详情页解析（:100-108）。
  - 列表为空但 bookUrlPattern 非空时，返回空列表。
- **详情页项的 bookUrl**：发生过重定向时取 res.url；否则取 `getAbsoluteURL(url, ruleUrl)`，**带着 `,{选项}`**（:165-169）。这时以 `canReName=false` 走 BookInfo 解析，并把当前页面存进 `infoHtml`。
- **列表前缀**：先判 `-`（倒序），再判 `+`（只是去掉）。`+-x` 不会倒序（:90-96）。
- **发现**：ruleExplore.bookList 为空时，整套改用搜索规则（:84-88）。
- **每一项的字段**（:211-288）：
  - `name`：用 formatBookName 去掉 `\s+作\s*者.*|\s+\S+\s+著` 再 trim。**为空就丢掉这一项**。
  - `author`：去掉 `^\s*作\s*者[:：\s]+|\s+著`（AppPattern.kt:35-36）。
  - `kind`：取字符串列表，用 `,` 连接，截前 1000 字。
  - `wordCount`：纯整数（可带负号）时按规则格式化：大于 10000 输出 `#.#万字`，1 到 10000 输出 `N字`，小于等于 0 输出空；不是纯整数则原样保留（StringUtils.kt:276-293）。
  - `lastChapter`：原样。
  - `intro`：`HtmlFormatter.format` 后截前 5000 字。
  - `coverUrl`：非空时对 res.url 求绝对地址。
  - `bookUrl`：用 isUrl 取值，空时退回 res.url。如果它等于 res.url，就把当前页存进 infoHtml。
  - kind、wordCount、lastChapter、intro、coverUrl 出错都被吞掉；**name、author、bookUrl 出错会让整个搜索失败**。
- **去重**：按 bookUrl 用 LinkedHashSet，保留第一次出现的。去重后**再**按 `-` 倒序（:142-147）。
- **过滤**：普通搜索不按名称或作者丢弃结果。只有精准搜索会传入 `name== && author==` 的过滤，并在拿到第一条后停止（WebBook.kt:484-485）。过滤发生在取完 kind 之后。

## 5. 详情（BookInfo.kt）

- 已有 infoHtml 时不发请求（WebBook.kt:251）。否则以书源 URL 为 base 请求 bookUrl。规则的 baseUrl 是 bookUrl，redirectUrl 是 res.url。
- **init**：非空时，用 `getElement` 的结果替换当前上下文（:58-64）。**匹配不到会返回 null，`setContent(null)` 抛 AssertionError**（AnalyzeRule.kt:99）。
- **name / author**：清洗方式同搜索。只有在 `canReName 入参为 true 且规则 canReName 非空白`（写 `"false"` 也算非空白），或书上原值为空时，才会覆盖（:65-81）。
- **kind、wordCount、lastChapter、coverUrl**：只在取到非空值时写入，出错吞掉。封面相对 redirectUrl 求绝对地址。
- **intro**：trimStart 后以 `<usehtml>`、`<md>`、`<useweb>` 开头的原样保留，否则 format 后截 5000 字（:126-139）。
- **tocUrl**：用 isUrl 取值，为空时取 baseUrl（也就是 bookUrl，**不是**重定向后的地址）。如果它等于 baseUrl，就把 body 存进 `tocHtml`（:163-167）。
- **文件类书源**：改取 downloadUrls，为空时抛「下载链接为空」。

## 6. 目录（BookChapterList.kt）

- 满足 `bookUrl==tocUrl` 且有 tocHtml 时不发请求。否则以 bookUrl 为 base 请求 tocUrl（WebBook.kt:330-360）。
- **每一项**（:232-271）：
  - `title`、`url` 用 getString 取值，**url 不转绝对地址**，只记下 `chapter.baseUrl=本页 redirectUrl`。到正文阶段才用 `getAbsoluteURL()` 拼接，并保留 `,{}` 选项（BookChapter.kt:147-158）。
  - `updateTime` 存进 `tag`。
  - isVolume、isVip、isPay 用 `isTrue` 判断：空白和 `"null"` 算 false；不区分大小写匹配 `false|no|not|0|0.0` 的算 false；其余都算 true（StringExtensions.kt:75-80）。
  - url 为空时：卷用 `title+本页元素序号`，普通章节用本页的 baseUrl。
  - title 为空就丢掉。
- **下一页**：用 `getStringList(isUrl)` 取，结果已去重、去空，并排除了本页的 redirectUrl（:208-216）。
  - **只有 1 个下一页时串行翻页**：用 `已访问列表`（初始值是首页 redirectUrl）防止循环，每页只取第一个下一页。后续页的 redirectUrl 用的是 nextUrl，而**不是** res.url。body 为 null 时停止（:74-95）。
  - **有多个下一页时**，只用首页给出的那一批并发抓取，并发数取 threadCount（默认 16），结果保持原顺序（FlowExtensions.kt:112-128）。这些子页不再继续找下一页；`res.body!!` 为空时抛 NPE（:97-121）。
- 结果为空时抛 TocEmptyException（:123-125）。
- **倒序与去重**（:126-135）：
  - 没有 `-` 时：反转 → 按 url 去重 → 再反转。效果是保持原顺序、**重复的保留最后一次**。
  - 有 `-` 时：结果倒序，重复的保留原顺序里的第一次。
  - 用户开了 reverseToc 时，再整体翻转一次。
- 之后执行 formatJs（JS 接入点，:141-159），并更新书籍的统计字段。

## 7. 正文（BookContent.kt）

- **特殊情况**：
  - content 规则为空时，直接返回章节 url（WebBook.kt:400-403）。
  - 卷章节且 url 以 title 开头时，返回 tag（:404-407）。
- **请求**：url 是 `chapter.getAbsoluteURL()`，base 是 tocUrl。webJs、sourceRegex 只在 WebView 下生效。
- **单页处理**（:234-251）：
  1. 用 `getString(content, unescape=false)` 取正文。
  2. 音频、视频类书籍到此为止。
  3. 其余书籍：开了 adaptSpecialStyle 时，先用占位符保护 `<usehtml>…</usehtml>`。
  4. 调 `formatKeepImg(redirectUrl)`：
     - 先做 format：`&nbsp;` 变空格；`&ensp;`、`&emsp;` 变空格；删掉零宽字符；块级标签（div|p|br|hr|h\d|article|dd|dl）变换行；删注释；删掉除 img 以外的标签；换行统一成 `\n　　`，行首补 `　　`，删掉末尾空白（HtmlFormatter.kt:73-87）。
     - img 的 src 和 data-src 转成绝对地址，保留 `,{}` 选项（:151-182，正则请照抄，`[^>]*` 是贪婪的，会取最后一个 src）。
  5. 正文里含 `&` 时做 unescapeHtml4。
  6. 还原 usehtml 占位符。
- **下一页**：用 isUrl 取列表，不排除本页地址。
  - **只有 1 个时串行**。每轮先判断：这一页的绝对地址如果**等于下一章的绝对地址**（两者都对当前首页 redirectUrl 求绝对地址），就停止（:93-96）。后续页的 redirectUrl 用 res.url。
  - 多个时并发，并发数为 `threadCount` 限制在 1 到 4 之间，**不做下一章判断**（:119-143）。
  - 各页之间用 `\n` 拼接。
- **下一章 url 的来源**：没传入时，取数据库里 index+1 章的 url；没有下一章时**回绕到第 0 章**（:62-67）。
- **subContent**：结果以 http 开头就再请求一次。文本类书籍作为一页追加，音频类书籍存成 lyric（:144-163）。
- **title**：在首页上下文里取。用 imgRegex `(.*)((?:data|https?):[\s\S]+)$` 把内容拆成标题和 reviewImg 两部分，然后**写回数据库**（:165-188）。
- **replaceRegex**（:190-195）：每行先 trim，整段交给规则引擎替换，再在每行前加 `　　`（空行也加）。
- **空内容**：非卷章节内容为空白时，抛 ContentEmptyException（:204-206）。
- **imageStyle 不参与解析**：只在 ReadBook.kt:660-670 写进书籍配置。取值有 DEFAULT、FULL、TEXT、SINGLE（Book.kt:466-469）；SINGLE 会强制把翻页动画设为 0；漫画、PDF 默认 FULL。

## 8. 错误与边界汇总

- **会抛错的情况**：
  - searchUrl 为空。
  - body 为 null（报「Failed to access website:%s」）。
  - 详情页 init 匹配不到。
  - name、author、bookUrl、tocUrl 的规则出错。
  - 目录为空。
  - 正文为空。
  - 文件类书源的 downloadUrls 为空。
  - 非法的 URL 或 charset 名称。
  - 多页并发时 body 为空（NPE）。
- **返回空列表的情况**：bookUrlPattern 已设置、但地址不匹配且列表为空时。
- **测试模式**：`isTest` 下网络异常不抛出，改成在 callTime 里写错误码（-1 到 -7，AnalyzeUrl.kt:512-533）。

## 9. 容易移植错的点

- `{{key}}` 本质上是 JS 表达式，没有「纯模板」这条路径。
- 目录里没有链接的非卷章节，url 都会变成同一个 baseUrl，按 url 去重后**只剩一条**。卷的占位 url `title+序号` 是按每页内的序号算的，跨页可能撞车。
- Cookie 有两层，读取用的域不同：第一层用书源 URL 的域，网络层用实际请求的域；而且两层合并时谁优先也相反。
- 本文第 1、3 节里的几个意外，移植时同样要对齐：
  - 对象形式的 body 会以带缩进的 JSON 发出。
  - 指定 charset 后，已编码的值会被二次编码。
  - XML body 会被当成 JSON 发出。
  - 补了 XML 声明的响应不会再执行 bodyJs。
  - urlOption 的 charset 不影响响应解码。
- `getAbsoluteURL` 截断 base 用的是第一个逗号，而不是 `,{`。
- 搜索里直接命中详情页时，bookUrl 带着 `,{POST 选项}`。