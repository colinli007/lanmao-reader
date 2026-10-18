# Legado（legado-with-MD3 @ d1b488b）书源 JS 宿主 API 精确语义

> 源码根：`md3/app/src/main/java/io/legado/app/`（下文路径均相对此目录，Rhino 模块为 `md3/modules/rhino/...`）。
> 只读源码得出，未运行验证；标「推断」处为依据 Rhino/JDK 通用行为的推断。

---

## 0. 运行时总览（先读这一节，否则 `java.xxx` 的语义会搞错）

### 0.1 `java` 在不同上下文是不同对象

| 上下文 | `java` 实际是 | 绑定处 | 其它绑定 |
|---|---|---|---|
| 规则字段里的 `@js:` / `<js>` / `{{}}`（搜索列表、详情、目录、正文） | `AnalyzeRule` | `model/analyzeRule/AnalyzeRule.kt:832-847` | `cookie`=CookieStore, `cache`=CacheManager, `source`, `book`（=ruleData as BaseBook，搜索阶段是 SearchBook）, `result`, `baseUrl`, `chapter`, `title`, `src`(当前 content), `nextChapterUrl`, `rssArticle`, `fromBookInfo` |
| URL 规则（searchUrl/tocUrl/…里的 `@js:`、`<js>`、`{{}}`、URL 选项里的 `js`/`bodyJs`）、`loginCheckJs` | `AnalyzeUrl` | `model/analyzeRule/AnalyzeUrl.kt:363-387` | `baseUrl`, `cookie`, `cache`, `page`, `key`, `speakText`, `speakSpeed`, `book`（ruleData as Book，搜索时为 null）, `source`, `result`, `infoMap` |
| 书源级 JS：`header` 的 `@js:`、`loginUrl`/`login()`、`loginUi`、发现 `exploreUrl` 的 JS、回调 JS | 书源对象本身（`BaseSource`） | `data/entities/BaseSource.kt:332-351` | `source`=this, `baseUrl`=getKey(), `cookie`, `cache`（loginUi 额外 `result`={}, `book`=null, `chapter`=null，`:179-183`） |

三者都实现 `JsExtensions`（及其父接口 `JsEncodeUtils`），所以编码/网络/日志类方法三处都有；但 **`put/get`、`getString/getElements/setContent`、`refreshTocUrl`、`refreshExplore` 等只存在于特定实现**，且同名方法语义不同（见第 1 节）。

### 0.2 Rhino 类型映射（决定 JS 实际拿到什么）

- 引擎：Rhino 1.7.14，ES6 语言级别、解释模式、`instructionObserverThreshold=10000`（用于取消）、`FEATURE_ENABLE_JAVA_MAP_ACCESS=true`（`modules/rhino/.../RhinoScriptEngine.kt:321-338`）。
- `WrapFactory` 未关 `javaPrimitiveWrap`（默认 true，jar 字节码确认），因此 **Kotlin 方法返回的 `String` 在 JS 里是包装的 `java.lang.String` 对象**：`typeof` 为 `"object"`、`===` 与 JS 字符串字面量比较为 false，但原型回落到 JS `String.prototype`（`NativeJavaObject.getPrototype` 对 String 特判），所以 `.match/.replace/JSON.parse` 照常可用；同时 Java 方法 `.equals() .length() .getBytes() .isEmpty() .contains()` 也可用。
- `ByteArray` → `NativeJavaArray`（Java `byte[]`，元素为 **有符号** -128..127，有 `.length`）。
- `List` → `NativeJavaList`（可下标、`.length`、也可 `.get(i)/.size()`）；`Map` → `NativeJavaMap`（可 `m.key`/`m["key"]`，也可 `.get()`）。
- JS 数组传给 `Any` 参数：Rhino 的 `NativeArray` 实现了 `java.util.List`（ajax 的数组参数靠这个）。JS 对象传给 `Map` 参数：`NativeObject` 实现 `Map`。
- 书源对象由 `NativeBaseSource` 包装：除 `setVariable` 外，`setXxx` 若存在同名属性 `xxx` 则对 JS 隐藏；JS 只能写 `variable` 属性（`help/rhino/NativeBaseSource.kt:10-38`）。`BookChapter`、各 Rule、`Book.ReadConfig` 用 `ReadOnlyJavaObject`：属性只读、对应 setter 隐藏（`modules/rhino/.../ReadOnlyJavaObject.kt`，注册于 `App.kt:345-357`）。`Book` 不受限。

---

## 1. 变量与持久化

### 1.1 `java.put(key, value)` / `java.get(key)` —— 三种实现

**(a) AnalyzeRule（规则 JS，最常见）** `model/analyzeRule/AnalyzeRule.kt:801-827`

- 签名：`put(key: String, value: String): String`（返回 value，可链式）；`get(key: String): String`（永不为 null，缺省 `""`）。JS 传数字会被 Rhino 转成字符串。
- `put` 写入顺序（**只写第一个非 null 的接收者**，因为 `putVariable` 返回非 null Boolean，elvis 不会继续）：`chapter` → `book`（ruleData as BaseBook）→ `ruleData` → `source.put`（即 1.3 的持久化缓存）。
- `get` 特殊键：`"bookName"`→`book.name`，`"title"`→`chapter.title`（对应对象存在时）。否则按 `chapter` → `book` → `ruleData` → `source.get` 依次取 **第一个非空串**。
- 规则里的 `@put:{k:"rule"}` 与 `@get:{k}` 用的就是 **同一对 put/get**：`putRule` 对每个值先 `getString(rule)` 再 `put`（`:455-459`，解析 `:464-486`，正则 `putPattern` `:955`）；`@get:{k}` 在 `makeUpRule` 中调用 `get(k)`（`:759-760`）。`@put` JSON 先严格解析，失败再宽松解析并记一次调试日志。

**(b) AnalyzeUrl（URL 规则 JS）** `model/analyzeRule/AnalyzeUrl.kt:389-408`

- `put`：`chapter?.putVariable` → `ruleData?.putVariable`；**两者都为 null 时静默丢弃**（不落 source）。
- `get`：同样的 `bookName`/`title` 特判；`chapter` → `ruleData`，**没有 source 回落**。
- 搜索/发现阶段 ruleData 是一个新的 `RuleData`（纯内存 HashMap，`model/analyzeRule/RuleData.kt`），URL 阶段 put 的值会在列表解析时以 JSON 写进每个 SearchBook 的 `variable`（`model/webBook/WebBook.kt:61-90`，`BookList.kt:72,164,211`），列表每项再 `setRuleData(searchBook)`（`BookList.kt:174,216`）。

**(c) BaseSource（书源级 JS）** `data/entities/BaseSource.kt:282-294`

- `put(key,value)` → `CacheManager.put("v_${sourceKey}_${key}", value)`（**永久**：DB 表 `caches` + 内存 LRU，deadline=0）；`get` → `CacheManager.get(...) ?: ""`。
- AnalyzeRule 的 put 只有在 chapter/book/ruleData 全为 null 时才会走到这里（例如 RSS 以外基本不会）。

**生命周期小结**

| 存储位置 | 何时落盘 |
|---|---|
| `RuleData`（搜索/发现 URL 阶段） | 不落盘；复制进 SearchBook.variable |
| `Book.variable`（JSON，`<10000` 字符的值） | 随 Book 实体写库时（加入书架/更新详情后保存） |
| `BookChapter.variable` | 目录解析后随章节入库；正文阶段只有正文规则含标题时才 `bookChapterDao.update`（`model/webBook/BookContent.kt:186`） |
| 大值（`>=10000` 字符） | 立即写文件 `externalFiles/ruleData/book/md5(bookUrl)/md5(key).txt`（章节按 bookUrl+chapterUrl），`help/RuleBigDataHelp.kt:15-17,54-72`；`RuleData` 例外：大值仍留内存（`RuleData.kt`） |
| source.put | 立即写 DB `caches` |

### 1.2 `book.putVariable / getVariable`，`chapter.putVariable / getVariable`

- `RuleDataInterface.putVariable(key, value: String?): Boolean`（`model/analyzeRule/RuleDataInterface.kt:7-28`）：value 为 null → 删除；长度 `<10000` → 进 `variableMap` 并清掉大值文件；否则移出 map、写大值文件。`getVariable(key): String` → map → 大值 → `""`（`:32-34`）。
- `BaseBook.putVariable` 覆写：成功后把整个 map 序列化回 `variable` 字段（JSON 字符串），**恒返回 true**（`data/entities/BaseBook.kt:19-24`）。`BookChapter` 同样（`data/entities/BookChapter.kt:60-88`）。
- `Book.variableMap` 懒加载自 `variable` JSON（`data/entities/Book.kt:152-154`）。
- 另有 `book.putCustomVariable(v)` / `getCustomVariable()` = key `"custom"`（`BaseBook.kt:26-32`）。
- 注意没有无参 `book.getVariable()`；`book.variable` 属性可读到整段 JSON。

### 1.3 `source.getKey()` / `getTag()`

- BookSource：`getKey()` = `bookSourceUrl`，`getTag()` = `bookSourceName`（`data/entities/BookSource.kt:112-118`）；RssSource 为 `sourceUrl`/`sourceName`；HttpTTS 为 `"httpTts:$id"`/`name`。
- getKey 是所有按源隔离存储（变量、登录头、登录信息、cookie 域、验证结果）的命名空间。

### 1.4 `source.setVariable / putVariable / getVariable`

`data/entities/BaseSource.kt:240-270`

- `setVariable(variable: String?)`、`putVariable(variable: String?)`（两者等价）：非 null → `CacheManager.put("sourceVariable_${key}", v)`（永久，DB+内存）；null → `CacheManager.delete`。
- `getVariable(): String`：先返回 `temporaryVariable`（仅 BookSource 有，`@Ignore` 非持久，发现页 `ExploreBooksUseCase.kt:66` 会在拷贝上设置），否则 `CacheManager.get("sourceVariable_${key}") ?: ""`。
- 注：这是“书源自定义变量”（UI 里可编辑），与 `java.put` 的 `v_` 前缀是两份数据。

### 1.5 登录相关

| API | 行为 | 位置 |
|---|---|---|
| `source.getLoginHeader(): String?` | `CacheManager.get("loginHeader_${key}")` | `BaseSource.kt:136-139` |
| `source.getLoginHeaderMap(): Map?` | 上者宽松 JSON 解析 | `:141-144` |
| `source.putLoginHeader(header: String)` | 解析 JSON；若含 `Cookie`/`cookie` 键 → `CookieStore.replaceCookie(sourceKey, cookie)`（合并写入源域 cookie）；原始字符串永久存入 `loginHeader_${key}`。**JSON 不合法也照存**，只是不抽 cookie | `:149-156` |
| `source.removeLoginHeader()` | 删缓存 + `CookieStore.removeCookie(sourceKey)` | `:158-161` |
| 登录头生效方式 | `getHeaderMap(ua, hasLoginHeader=true)` 把登录头合并进请求头；`AnalyzeUrl` 默认 `hasLoginHeader=true`（`AnalyzeUrl.kt:93,132-140`），`webView` 系列也传 true | `BaseSource.kt:102-131` |
| `source.getLoginInfo(): String?` | 读 `userInfo_${key}`，用 **`AES/ECB/PKCS5Padding`、key=androidId 的 UTF-8 前 16 字节** 解密；任何异常（含 androidId 不足 16 字节，如 `"null"`）→ 记 AppLog、返回 null | `:167-177` |
| `source.putLoginInfo(info): Boolean` | 同 key AES 加密为 Base64 后永久存储；异常返回 false | `:218-229` |
| `source.getLoginInfoMap(): MutableMap<String,String>` | 有 loginInfo → 宽松 JSON 解析为 map（失败给空 map）；没有且 `loginUi` 非空 → 求值 loginUi（`@js:`/`<js>` 时先拼 `loginUrl` 的 JS 再执行），解析为 RowUi 数组，过滤 `type=="button"`，取 `name→default ?: ""`，**顺手 putLoginInfo 保存**并返回；否则空 map。JS 拿到 NativeJavaMap | `:185-213` |
| `source.removeLoginInfo()` | 删除 | `:231-234` |
| `source.login()` | 执行 loginUrl JS 后调用其中 `login` 函数，未定义则 `throw` | `:83-97` |

### 1.6 其它书源方法

- `source.refreshExplore()`（也就是发现 JS 里的 `java.refreshExplore()`，因为那里 `java`=source）：主线程调用直接 `error()`；清发现分类缓存（`BaseSource.kt:299-308`）。
- `source.refreshJSLib()`、`source.putConcurrent(rate)`（`:313-327`）。
- `source.getHeaderMap(ua, hasLoginHeader=false)`：`header` 支持 `@js:`/`<js>`，**每次构造 AnalyzeUrl 都会重新执行**；无 UA 则补全局 UA（`:102-131`）。

### 1.7 `book.setReverseToc(b)` / `book.upCustomIntro()` / `java.refreshTocUrl()` / `java.reGetBook()`

- `setReverseToc(Boolean)` 写 `book.config.reverseToc`（`Book.kt:239-245`）；目录解析末尾 `if (!book.getReverseToc()) list.reverse()`（`model/webBook/BookChapterList.kt:133`），所以在目录规则 JS 中调用会影响本次排序。
- `upCustomIntro()`：`customIntro = intro`（`Book.kt:186-188`）。
- `java.refreshTocUrl()`（AnalyzeRule）：**仅允许在 preUpdateJs 中**，否则抛 `NoStackTraceException("只能在 preUpdateJs 中调用")`；若来自详情页只记日志跳过；否则阻塞执行 `getBookInfoAwait`，超时 30 分钟（`AnalyzeRule.kt:938-952`）。`reGetBook()` 同限制，先精确搜索再取详情（`:913-933`）。

---

## 2. 规则解析类（仅 AnalyzeRule 上下文）

| API | 签名 / 返回 | 语义 | 位置 |
|---|---|---|---|
| `java.setContent(content, baseUrl?)` | `@JvmOverloads (Any?, String? = null): AnalyzeRule` | content 为 null 抛 `AssertionError("内容不可空…")`；重算 isJSON（非 Jsoup Node 时 `toString().isJson()`）；baseUrl 非 null 才更新；清空三种解析器缓存。**直接修改当前共享 AnalyzeRule 的 content**，影响同一条目后续字段，直到下一次框架调用 setContent | `AnalyzeRule.kt:97-117` |
| `java.getString(rule, mContent?, isUrl?)` | `(String?, Any? = null, Boolean = false): String`；另有 `(String?, unescape: Boolean)` | rule 空 → `""`；mContent 为 null 用当前 content；按规则模式（`@CSS:`/`@@`/`@XPath:`/`@Json:`/`$.`/`/`/`@js:`/`{{}}`/`##` 正则替换/`@put`）求值；结果含 `&` 时默认 `unescapeHtml4`；isUrl=true 时转绝对 URL（空则返回 baseUrl） | `:290-375` |
| `java.getStringList(rule, mContent?, isUrl?)` | `(String?, Any? = null, Boolean = false): List<String>?` | rule 空/结果 null → **null**；字符串结果按 `\n` 拆；isUrl 时去重并转绝对 URL | `:193-285` |
| `java.getElement(rule)` | `(String): Any?` | 注意：Jsoup/XPath 模式内部调用的是 `getElements`，**返回的是 Elements 列表而非单个元素**；JSON 模式返回对象；正则模式返回 List；空 rule → null | `:380-413` |
| `java.getElements(rule)` | `(String): List<Any>` | 永不 null（空返回 ArrayList）；Jsoup 模式返回 `org.jsoup.select.Elements`，元素是 Jsoup `Element`（JS 里会调 `.text()/.attr()/.select()/.html()` 等 Jsoup API） | `:419-450` |
| 规则 `{{js}}` 结果格式化 | Double 且整数 → `"%.0f"`（Locale.ROOT），其余 `toString()`；null 不插入 | `:745-755` |

---

## 3. 网络

公共事实：
- OkHttp 全局客户端：connect 15s / write 15s / read 60s / **call 60s**，跟随重定向，信任所有证书，`retryOnConnectionFailure`；无 UA 时补全局 UA，UA 值为 `"null"` 时删除 UA；加 `Keep-Alive`；100MB HTTP 缓存（`help/http/HttpHelper.kt:72-133`）。
- 响应解码：**不使用 URL 选项的 charset**，顺序为 Content-Type charset → HTML `<meta>` 探测（`help/http/OkHttpUtils.kt:51-58,79-95`）；先去 UTF-8 BOM。
- **非 2xx 不抛异常**：返回错误页 body；`retry` 只在 `!isSuccessful` 时重发（`OkHttpUtils.kt:29-42`）。
- 源并发率 `concurrentRate` 限流（`help/ConcurrentRateLimiter.kt`）。

### 3.1 `java.ajax(url[, callTimeout])`

- 签名：`ajax(url: Any): String?`、`ajax(url: Any, callTimeout: Long?): String?`（`help/JsExtensions.kt:107-131`；AnalyzeRule 覆写 `AnalyzeRule.kt:882-908`）。
- url 为 `List`（含 JS 数组）时 **只取第一个元素** `firstOrNull().toString()`，其它忽略；否则 `toString()`。
- 走完整 `AnalyzeUrl`：支持 `url,{json选项}`（method/body/headers/charset/type/webView/webJs/js/bodyJs/retry/dnsIp/serverID/webViewDelayTime，`AnalyzeUrl.kt:811-988`）、`<js>`/`@js:`、`{{}}`、`<1,2,3>` 页码（ajax 不传 page，页码段被保留原样）。
- **不传 baseUrl**：相对 URL 不会被补全（AnalyzeRule 版也没传）。AnalyzeRule 版额外传 `ruleData = book`，所以 URL 里的 `{{}}` 可读 book 变量。
- 请求头：书源 header（含 header JS 执行结果）+ 登录头 + URL 选项 headers；`proxy` 头被摘出作代理（`AnalyzeUrl.kt:128-143`）。
- Cookie：发送前把 **按书源 key 计算的域**（`NetworkUtils.getSubDomain(source.getKey() ?: url)`，`AnalyzeUrl.kt:142`）的 cookie 合并进 `Cookie` 头（`setCookie()`，`:706-728`）——即 **ajax 到第三方域名时带的也是书源主域的 cookie**；启用 cookieJar 时网络拦截器再按请求 URL 的域加载/保存 cookie。
- 超时：callTimeout（毫秒）覆盖 OkHttp callTimeout，否则 60s（`:599-623`）。
- URL 选项 `type` 存在时：**返回响应字节的十六进制字符串**（`:420-422`）。`webView:true` 时走后台 WebView。
- 出错：**不抛异常**，返回异常堆栈字符串 `stackTraceStr`；JsExtensions 版记 `AppLog.put`，AnalyzeRule 版记 `log()`（调试台）+ printOnDebug；协程已取消时 `ensureActive()` 会把取消异常抛出。
- 返回 `body`（可能为 null）。

### 3.2 `java.ajaxAll(urls[, skipRateLimit])` / `ajaxTestAll(urls, timeout[, skipRateLimit])`

- `ajaxAll(Array<String>): Array<StrResponse>`；并发数 = 设置里的 `threadCount`；**任一失败整体抛异常**（无 catch）；结果顺序与输入一致（flow `mapAsync` + toList，推断保序）。`skipRateLimit` 跳过源限流（`JsExtensions.kt:136-150`）。
- `ajaxTestAll`：带 callTimeout，`isTest=true` 时异常不抛，返回 `StrResponse(url, e.message)`，`callTime` 填错误码（-1 超时、-2 SocketTimeout、-3 UnknownHost、-4 ConnectException、-5 Socket、-6 SSL、-7 其它）（`:155-174`，`AnalyzeUrl.kt:512-533`）。

### 3.3 `java.connect(url[, header[, callTimeout]])`

- `connect(String): StrResponse`；`connect(String, header: String?)`；`connect(String, String?, Long?)`（`JsExtensions.kt:180-217`）。
- header 是 **JSON 字符串**；解析成功时作为 `headerMapF` **整体替换书源 header 与登录头**（AnalyzeUrl 中 headerMapF 非 null 就不调 `getHeaderMap`）；解析失败/为 null 时回落书源 header。
- 出错不抛：返回 `StrResponse(url, 堆栈)`，其 `code()==200`、`message()=="OK"`（伪造响应，`help/http/StrResponse.kt:30-43`）。
- `StrResponse` 方法：`body()`、`url()`（有 networkResponse 时取最终 URL）、`code()`、`message()`、`headers()`、`isSuccessful()`、`raw()`、`callTime()`、`errorBody()`（`StrResponse.kt:16-87`）。

### 3.4 `java.get / post / head`（Jsoup，非 AnalyzeUrl）

`JsExtensions.kt:504-583`

- `get(url, headers: Map<String,String>[, timeout: Int?]): org.jsoup.Connection.Response`；`head(...)` 同；`post(url, body: String, headers[, timeout])`。
- Jsoup 直连：**不解析 URL 选项、不带书源 header/登录头/cookie、不保存响应 cookie**、`followRedirects(false)`（用于拿 302 的 `Location`）、`ignoreContentType(true)`、信任所有证书、默认超时 30000ms、受源并发率限制。
- 书源启用 cookieJar 时会往 headers 里加 `CookieJar: 1`——该头只被 OkHttp 拦截器识别，Jsoup 会 **原样发给服务器**（无实际 cookie 效果）。
- Jsoup 1.16.2 默认：状态码 ≥400 抛 `HttpStatusException`（未设 ignoreHttpErrors），3xx 不抛；默认 maxBodySize 限制（推断 2MB）会截断大响应。
- JS 常用：`res.body()`、`res.header("Location")`、`res.headers()`、`res.cookies()`、`res.statusCode()`、`res.url()`。

### 3.5 `java.getStrResponse(...)`（AnalyzeUrl 上下文，例如 loginCheckJs）

- `@JvmOverloads getStrResponse(jsStr: String? = null, sourceRegex: String? = null, useWebView: Boolean = true): StrResponse`，即用当前 AnalyzeUrl 重新请求；**异常直接抛出**（`AnalyzeUrl.kt:536-545`）。

### 3.6 WebView 类（Android 专属）

- `java.webView(html, url, js[, cacheFirst])`：`String?`；必须非主线程否则 `error()`；后台 WebView 加载 html（有 html 时以 url 为 base）或 url，执行 js 取值（无 js 返回整页源码）；带书源 header+登录头；**cacheFirst 参数被忽略**（没传给 BackstageWebView）；默认超时 60s，超时抛 `TimeoutCancellationException`（`JsExtensions.kt:219-244`，`help/http/BackstageWebView.kt:44-66`）。
- `webViewGetSource(..., sourceRegex[, cacheFirst[, delayTime]])`：拦截匹配正则的资源 URL 返回；`webViewGetOverrideUrl(..., overrideUrlRegex, ...)`：拦截匹配的跳转 URL（`:246-331`）。
- `java.getWebViewUA()`：`WebSettings.getDefaultUserAgent(appCtx)`（`:715-718`）。

### 3.7 人机交互类（Android UI，阻塞）

- `java.startBrowser(url, title[, html])`：打开内置浏览器 Activity，**不等待**，返回 Unit；源为 null 抛异常；url 长度须 <64K（`JsExtensions.kt:338-345`，`help/source/SourceVerificationHelp.kt:78-95`）。
- `java.startBrowserAwait(url, title[, refetchAfterSuccess=true[, html]]): StrResponse`：打开浏览器并 **阻塞当前线程**（`LockSupport.parkNanos` 每次 1 分钟循环，**无总超时**）直到页面回写结果；结果为空串抛 `NoStackTraceException("验证结果为空")`；整个方法 `@Synchronized`，**全局同一时刻只能有一个验证**；主线程调用抛异常；返回 `StrResponse(结果url.ifEmpty{url}, body)`（`JsExtensions.kt:350-370`，`SourceVerificationHelp.kt:32-72`）。
- `java.getVerificationCode(imageUrl): String`：弹图片验证码对话框，阻塞等待用户输入，空则抛（`JsExtensions.kt:375-378`）。
- `java.openUrl(url[, mimeType])`：`legado://`/`yuedu://` 打开导入页，否则弹确认后外部打开（`:1161-1185`）。

### 3.8 文件 / 下载 / 脚本导入

- `java.downloadFile(url): String`：经 AnalyzeUrl 下载到 `外部缓存目录/md5_16(url).{type 或 URL 后缀}`，返回相对路径；失败抛（`:446-469`）。
- `java.cacheFile(url[, saveTime 秒])`、`java.importScript(path)`：key=`md5Encode16(url)`，`CacheManager` 存路径、文件不存在时重新下载并 `log("首次下载…")`；按 `EncodingDetect` 猜编码读文本；importScript 内容为空抛异常（`:383-422`）。
- `getFile/readFile/readTxtFile/deleteFile/unzipFile/un7zFile/unrarFile/unArchiveFile/getTxtInFolder/getZipStringContent/getRarStringContent/get7zStringContent/...ByteArrayContent`：全部限制在 `appCtx.externalCache` 下，canonicalPath 越界抛 `SecurityException("非法路径")`（`:727-965`）。
- `java.queryTTF(data[, useCache=true])`：url / base64 / byte[]，SHA-256 为键缓存在 4 项 LRU；出错记日志并重抛（`:987-1032`）。`replaceFont(text, err, correct[, filter])`（`:1040-1083`）。

---

## 4. Cookie（`cookie` = `CookieStore` 单例）

### 4.1 Key 归一化

`NetworkUtils.getSubDomain(url)`（`utils/NetworkUtils.kt:197-228`）：
1. 仅当以 `http://`/`https://` 开头才处理，否则 **原样返回输入**（例如传 `"abc"` 就以 `"abc"` 为 key）；
2. 取 host；IP 直接返回 IP；
3. 否则 `PublicSuffixDatabase.getEffectiveTldPlusOne(host)`（OkHttp 内置 PSL）→ **eTLD+1**，如 `www.biquge.com.cn → biquge.com.cn`；失败返回 baseUrl。
- 端口、协议、路径都被丢弃：同一 eTLD+1 下所有子域、http/https 共享一份 cookie。

### 4.2 存储

- 持久：Room 表 `cookies`（主键 url=域）+ 内存 LRU 键 `"${domain}_cookie"`；会话（非 persistent）cookie 仅内存 `"${domain}_session_cookie"`，重启丢失（`help/http/CookieManager.kt:19-22,81-94`）。
- 响应写入（仅 cookieJar 启用时由 OkHttp 网络拦截器触发）：persistent 的合并进持久，非 persistent 的合并进会话（`CookieManager.kt:41-50`）。

### 4.3 方法

| API | 行为 | 位置 |
|---|---|---|
| `cookie.getCookie(url): String` | 持久(内存优先否则 DB) 与会话 cookie 合并（会话覆盖同名）；拼成 `k=v; k2=v2`；**若总长 >4096，随机删键直至 ≤4096 且真的从存储删除** | `help/http/CookieStore.kt:54-70` |
| `cookie.getKey(url, key): String` | 在 getCookie 结果里取单键，缺省 `""` | `:72-77` |
| `cookie.setCookie(url, cookie: String?)` | **覆盖**（非合并）写 DB 与内存；null 存空串；异常只记 AppLog | `:25-34` |
| `cookie.replaceCookie(url, cookie)` | 与旧持久 cookie 按键合并后 setCookie；url/cookie 空则什么都不做 | `:36-49` |
| `cookie.removeCookie(url)` | 删 DB、删内存持久与会话；**并清 Android WebView CookieManager**（对 host 与 eTLD+1 各写过期 cookie，`utils/CookieManagerExtensions.kt:9-22`） | `:79-85` |
| `cookie.cookieToMap(str)` / `mapToCookie(map)` | 按 `;` 与首个 `=` 切分；**值为空的键被丢弃**；拼接用 `"; "` | `:87-117` |
| `java.getCookie(tag[, key])` | key 为 null → `CookieStore.getCookie(tag)`，否则 `getKey` | `help/JsExtensions.kt:427-439` |

---

## 5. 缓存（`cache` = `CacheManager` 单例）

`help/CacheManager.kt`

| API | 存储 | 过期 / 生命周期 | 位置 |
|---|---|---|---|
| `cache.put(key, value[, saveTime=0 秒])` | value 为 `ByteArray` → ACache 文件；其余 `value.toString()` → 内存 LRU（50MB 上限）+ Room 表 `caches`（key, value, deadline） | saveTime=0 永不过期；否则 `deadline = now + saveTime*1000`，**`saveTime*1000` 是 Int 乘法，saveTime > 2147483 秒（约 24.8 天）会溢出**，得到错误甚至过去的 deadline | `:57-70` |
| `cache.get(key): String?` | 先内存（**命中即返回，不检查 deadline**），再查 DB 且未过期才返回并回填内存 | 过期仅在 DB 路径生效；内存条目直到被 LRU 淘汰或重启 | `:85-96` |
| `cache.get(key, onlyDisk)` | onlyDisk=true 只查 DB | | `:98-107` |
| `cache.getInt/getLong/getDouble/getFloat` | 内存同类型 → DB 解析 | | `:109-135` |
| `cache.putMemory/getFromMemory/deleteMemory` | 仅内存 LRU（值 Any） | 重启丢 | `:72-83` |
| `cache.putFile(key, value[, saveTime])` / `cache.getFile(key)` | ACache 文本文件：`context.cacheDir/ACache/<key.hashCode()>`，过期信息写在文件头 | 读取时过期则删除并返回 null；位于系统可清理的 cacheDir，总量上限 50MB | `:141-147`；`utils/ACache.kt:34-43,109-114,121-140,477-497,712-714` |
| `cache.getByteArray(key)` | ACache 二进制 | | `:137-139` |
| `cache.delete(key)` | 同时删 DB、内存、ACache 文件 | | `:149-153` |

- JS 把对象传给 `put` 会存成 `"[object Object]"`（Rhino toString），需自行 `JSON.stringify`。
- 用 `put` 存 byte[] 后，`get` 取不到（在 ACache 里）。
- 书源变量、登录头、登录信息、cookie 都复用这套缓存（键前缀 `v_`、`sourceVariable_`、`loginHeader_`、`userInfo_`、`${domain}_cookie`），`AppCacheManager.clearSourceVariables` 只清内存（`:35-45`）。

---

## 6. 编码、摘要、加解密

### 6.1 Base64 / Hex / 字节

| API | 签名 → 返回 | 行为 | 位置 |
|---|---|---|---|
| `base64Decode(str)` | `(String?) → String` | null → `""`；**Hutool 宽容解码**（先删所有空白，容忍缺 `=`、URL-safe `-_`）；按 **UTF-8** 转字符串；非法输入的处理遵 Hutool（推断：跳过非法字符不抛） | `JsExtensions.kt:606-609`，`help/crypto/CryptoUtils.kt:30-35` |
| `base64Decode(str, charset)` | `(String?, String) → String` | 同上，按指定字符集；未知字符集抛 | `:611-614` |
| `base64Decode(str, flags)` | `(String, Int) → String` | **Android `Base64.decode(str, flags)`**（严格得多：非法字符抛 `IllegalArgumentException("bad base-64")`，URL-safe 字符需 `URL_SAFE=8`），按平台默认字符集（Android 为 UTF-8） | `:616-619`，`utils/EncoderUtils.kt:30-34` |
| `base64DecodeToByteArray(str[, flags=0])` | `(String?[, Int]) → ByteArray?` | null/空白 → **null**；Android Base64 严格解码 | `:621-633` |
| `base64Encode(str[, flags=2])` | `(String[, Int]) → String?` | UTF-8 字节，Android Base64；默认 `NO_WRAP(2)`；flags=0 会每 76 字符换行并带尾换行 | `:635-643`，`EncoderUtils.kt:36-44` |
| Android flags 取值 | `DEFAULT=0, NO_PADDING=1, NO_WRAP=2, CRLF=4, URL_SAFE=8, NO_CLOSE=16`，可按位或 | | |
| `hexDecodeToByteArray(hex)` | `ByteArray?` | 奇数长度抛 `IllegalArgumentException`；非法字符抛 `NumberFormatException` | `:646-648`，`CryptoUtils.kt:21-26` |
| `hexDecodeToString(hex)` | `String?` | 同上后按 UTF-8 | `:651-654` |
| `hexEncodeToString(str)` | `String?` | UTF-8 → **小写** hex | `:657-660`，`CryptoUtils.kt:11-19` |
| `strToBytes(str[, charset="UTF-8"])` / `bytesToStr(bytes[, charset])` | | | `:586-601` |

### 6.2 摘要 / HMAC

| API | 行为 | 位置 |
|---|---|---|
| `md5Encode(str): String` | `MessageDigest("MD5")` over **UTF-8**，32 位 **小写** hex | `JsEncodeUtils.kt:21-24`，`utils/MD5Utils.kt:13-15` |
| `md5Encode16(str): String` | 32 位结果的 `substring(8, 24)`（小写） | `:26-29`，`MD5Utils.kt:21-25` |
| `digestHex(data, algorithm)` / `digestBase64Str(data, algorithm)` | JCA 算法名（`MD5`、`SHA-1`、`SHA-256`…）；UTF-8；hex 小写；Base64 为 Android NO_WRAP | `:466-486` |
| `HMacHex(data, algorithm, key)` / `HMacBase64(...)` | `Mac.getInstance(algorithm)`（如 `HmacSHA256`、`HmacMD5`，JCA 名大小写不敏感）；key 与 data 均 UTF-8；**空 key 会抛**（`SecretKeySpec` 拒绝空数组） | `:498-525`，`CryptoUtils.kt:51-55` |

### 6.3 `createSymmetricCrypto` 与 `SymmetricCryptoAndroid`

工厂重载（`JsEncodeUtils.kt:45-80`）：
- `(transformation: String, key: ByteArray?, iv: ByteArray?)`：key 为 null → **随机密钥**；iv 非 null 且非空才 `setIv`。
- `(transformation, key: ByteArray)`、`(transformation, key: String)`、`(transformation, key: String, iv: String?)`：String 版 key/iv 按 **UTF-8** 转字节（`encodeToByteArray`）。
- 无 `(String, ByteArray, String)` 混合重载。推断：JS 里 byte[] key + 字符串 iv 时 Rhino 可能把 byte[] 经 toString 匹配到全 String 重载，得到 `"[B@…"` 作为密钥，静默算错。

实现（`help/crypto/SymmetricCryptoAndroid.kt`，**MD3 分支已不用 Hutool 的 SymmetricCrypto**）：
- transformation 不含 `/` 时补成 **`"$alg/ECB/PKCS5Padding"`**（`:18`）；密钥算法 = `/` 前部分（`:19`）。
- 密钥规整（`:24-28`）：仅 **DES 超过 8 字节截到 8**、**DESede 超过 24 字节截到 24**；**AES 不补齐也不截断**：长度不是 16/24/32 时在第一次 encrypt/decrypt 的 `Cipher.init` 抛 `InvalidKeyException`（创建对象时不报错）。DESede 16 字节密钥能否用取决于 Android 提供者（推断 BC 接受 2-key 3DES）。
- IV（`:35-42`）：未设 IV，或 transformation 含 `/ECB/`（忽略大小写）→ 不带 IV 初始化（**ECB 下传入的 IV 被忽略**）；否则 `IvParameterSpec(iv)`，长度不符抛 `InvalidAlgorithmParameterException`。CBC 等模式未给 IV：加密时 JCE 随机生成 IV 且不输出（结果无法解密），解密时抛异常。
- **不支持 `ZeroPadding`**（直接交给 `Cipher.getInstance`，Android 无此填充 → `NoSuchPaddingException`）；上游 Hutool 版支持 ZeroPadding，此处行为不同。`PKCS7Padding` 是否可用取决于 Android 提供者（推断可用，等价 PKCS5）。
- 每次调用新建 `Cipher`，对象可复用。

对象方法：

| 方法 | 输入 → 输出 | 说明 |
|---|---|---|
| `encrypt(data)` | ByteArray / String（UTF-8）/ (String, charset: String?) / (String, Charset?) / InputStream → ByteArray | `:44-54` |
| `encryptBase64(data)` | 同上各重载 → String | 标准 Base64、带 `=`、不换行（Kotlin `Base64.Default`）`CryptoUtils.kt:28` |
| `encryptHex(data)` | ByteArray/String/InputStream → 小写 hex | `:95-99` |
| `encryptStr(data)` | → `String(密文, UTF-8)`（有损，几乎无用） | `:105-107` |
| `decrypt(data: String)` | **自动识别**：全为 hex 字符且长度为偶数 → 按 hex；否则 Hutool 宽容 Base64 | `:78-85`；全部由 0-9a-f 组成的偶数长度 Base64 会被误判为 hex |
| `decrypt(ByteArray / InputStream)` | → ByteArray | |
| `decryptStr(data)` | String/ByteArray/InputStream → **UTF-8** 字符串；无 charset 重载 | `:89-93` |
| `decryptHex(String)` / `decryptBase64(String)` | 强制格式 → ByteArray | `:101-103` |
| `setIv(ByteArray)` | 返回自身 | `:30-33` |

所有加解密错误（padding 错、key 长度错、格式错）**直接抛异常**到 JS，不记日志、不返回 null。

### 6.4 旧版便捷函数（均 `@Deprecated`，内部转调 createSymmetricCrypto；key/iv 为字符串时按 UTF-8；iv 传 `""` 等于无 IV）

| API | 实际行为 | 位置 |
|---|---|---|
| `aesDecodeToByteArray(str, key, transformation, iv)` | `.decrypt(str)`（hex/base64 自动识别） | `JsEncodeUtils.kt:113-117` |
| `aesDecodeToString(...)` | `.decryptStr(str)` | `:131-135` |
| `aesBase64DecodeToByteArray(...)` / `aesBase64DecodeToString(...)` | 与上两者**完全相同**（同样自动识别，不强制 Base64） | `:178-200` |
| `aesDecodeArgsBase64Str(data, key, mode, padding, iv)` | transformation=`AES/$mode/$padding`；**key、iv 先 Android Base64(NO_WRAP) 解码** | `:152-164` |
| `aesEncodeToByteArray(...)` | `.encrypt(data)` | `:214-218` |
| `aesEncodeToString(...)` | **Bug：实际调用 `decryptStr(data)`（解密）** | `:232-236` |
| `aesEncodeToBase64ByteArray(...)` | `encryptBase64(data).toByteArray()` | `:250-254` |
| `aesEncodeToBase64String(...)` | `.encryptBase64(data)` | `:268-272` |
| `aesEncodeArgsBase64Str(data, key, mode, padding, iv)` | **与名字和注释不符：key、iv 不做 Base64 解码**，直接 UTF-8 | `:290-298` |
| `desDecodeToString` / `desBase64DecodeToString` | `.decryptStr(data)`（两者相同） | `:306-321` |
| `desEncodeToString` | `String(encrypt(data))`（平台默认字符集，有损） | `:328-332` |
| `desEncodeToBase64String` | `.encryptBase64(data)` | `:339-343` |
| `tripleDESDecodeStr(data, key, mode, padding, iv)` | `DESede/$mode/$padding`，key/iv UTF-8 | `:361-369` |
| `tripleDESDecodeArgsBase64Str` | **key Base64 解码，iv 仍是 UTF-8** | `:386-398` |
| `tripleDESEncodeBase64Str` / `tripleDESEncodeArgsBase64Str` | 同上规律，输出 Base64 | `:416-454` |

### 6.5 非对称加密 / 签名（长尾）

- `createAsymmetricCrypto(transformation)`：`setPublicKey/setPrivateKey(ByteArray|String)`，`encrypt/decrypt/decryptStr/encryptHex/encryptBase64(data, usePublicKey=true)`（`JsEncodeUtils.kt:84-89`，`help/crypto/AsymmetricCrypto.kt`）。
- `createSign(algorithm)`：`setPrivateKey/setPublicKey(ByteArray|String)`（String 版直接 UTF-8 字节当 DER，**不做 Base64/PEM 解码**），`sign/signHex/verify`（`help/crypto/Sign.kt:14-68`）。

---

## 7. 文本 / 时间 / 杂项

| API | 签名 → 返回 | 精确行为 | 位置 |
|---|---|---|---|
| `java.timeFormat(time)` | `(Long) → String` | `FastDateFormat("yyyy/MM/dd HH:mm")`，**设备默认时区 + 默认 Locale**；参数为毫秒时间戳（JS 小数被截断成 long） | `JsExtensions.kt:677-680`，`constant/AppConst.kt:40-42` |
| `java.timeFormatUTC(time, format, sh)` | `(Long, String, Int) → String?` | `SimpleTimeZone(sh, "UTC")`：**`sh` 是毫秒偏移量**（不是小时；北京时间应传 `28800000`）；格式串为 Java `SimpleDateFormat` 语法；Locale 为设备默认 | `:665-672` |
| `java.encodeURI(str[, enc="UTF-8"])` | `String` | **`java.net.URLEncoder.encode`**（表单编码）：空格→`+`，`*` `-` `_` `.` 不编码，`~` `!` `'` `(` `)` 等全编码，与 JS `encodeURI`/`encodeURIComponent` 都不同；异常（非法 enc）返回 `""` | `:682-698` |
| `java.t2s(text)` / `java.s2t(text)` | `String` | 库 `com.github.liuyueyi.quick-chinese-transfer:quick-transfer-core:0.2.17`（词典随库内置，推断源自 OpenCC）；`t2s` 首次调用前 **加载一份排除词表**（约 100 个词如“雪糕”“晶片”“規則”等不做繁转简），`s2t` 无修正 | `:705-713`，`utils/ChineseUtils.kt:10-49`，`gradle/libs.versions.toml:64` |
| `java.toNumChapter(s)` | `(String?) → String?` | null → null；正则 **`(第)(.+?)(章)`**（`constant/AppPattern.kt:40`）找第一个匹配，把中间部分经 `StringUtils.stringToInt` 转成数字，返回值只有 `group1+数字+group3`，即 `"第${n}章"`，**匹配前后的其它文字都丢失**（`"正文 第十章 风起"` → `"第10章"`）；无匹配原样返回。`stringToInt`：全角转半角、去空白、`Integer.parseInt`，失败走 `chineseNumToInt`（支持 零一二…十百千万亿、〇壹贰叁…拾佰仟、两；含其它字符返回 **-1** → `"第-1章"`）。`chineseNumToInt` 第 188 行的“逐位数字”分支正则只匹配单字符，永不命中（死代码），但通用算法仍能把“一零二五”算成 1025 | `JsExtensions.kt:1089-1098`，`utils/StringUtils.kt:34-55,162-247` |
| `java.htmlFormat(str)` | `String` | `HtmlFormatter.formatKeepImg` | `:700-703` |
| `java.randomUUID()` | `String` | Kotlin `Uuid.random()`（v4，小写带连字符） | `:1151-1154` |
| `java.toURL(url[, baseUrl])` | `JsURL` | 字段 `host`、`origin`、`pathname`、`searchParams`（Map，值 URL 解码；无 `=` 的参数会越界抛）；**`origin` 实现有 bug**：拼进了整个 URL（`"$protocol://$host:$mUrl"`） | `:1101-1107`，`utils/JsURL.kt:9-38` |

---

## 8. 日志 / 提示 / 设备

| API | 行为 | Android 依赖 | 位置 |
|---|---|---|---|
| `java.log(msg): Any?` | `Debug.log(source.getKey(), msg.toString())`：**只有当该源正处于调试会话（`debugSource == key`）时**才输出到调试台，前缀 `[mm:ss.SSS]` 相对调试开始时间；无源时用当前调试源；另外若设置开启“记录日志”则 `AppLog.putDebug("${tag ?: "源"}调试输出: $msg")`；**返回原 msg 对象**（可内联：`return java.log(x)`）；协程已取消时抛 | 否（但输出目标是 App 调试 UI） | `JsExtensions.kt:1128-1135`，`model/Debug.kt:39-80`，`constant/AppLog.kt:61-65` |
| `java.logType(any)` | 输出 `any.javaClass.name` 或 `"null"` | 否 | `:1140-1146` |
| `java.toast(msg)` | UI 线程弹自定义 View 短 Toast，文本 `"${source.getTag()}: $msg"`（无源时为 `"null: …"`）；取消上一个 JS Toast；内部异常吞掉；返回 Unit | 是 | `:1112-1115`，`utils/ToastUtils.kt:74-87` |
| `java.longToast(msg)` | 同上，`LENGTH_LONG` | 是 | `:1120-1123`，`ToastUtils.kt:93-95` |
| `java.androidId()` | `Settings.Secure.ANDROID_ID`，取不到为 `"null"` | 是（设备 ID） | `:1156-1159`，`AppConst.kt:55-57` |
| `java.getWebViewUA()` | 系统 WebView 默认 UA | 是 | `:715-718` |
| `java.getReadBookConfig/getThemeMode/getThemeConfig(...Map)` | App 配置 JSON | 是（App 设置） | `:1190-1218` |

---

## 9. 移植陷阱清单

1. **`java` 身份三变**：同一个 `java.put/get` 在规则 JS、URL JS、书源级 JS 中分别写 chapter/book/ruleData/源缓存、只写 chapter/ruleData（否则丢弃）、写永久源缓存。Dart 版必须按上下文注入不同实现，不能做成一个全局对象。
2. **put 只写第一个非 null 接收者**，get 取第一个非空值；`bookName`、`title` 是保留键。
3. **ajax 永不抛**：错误时返回堆栈文本；非 2xx 返回错误页 body；`connect` 出错返回伪造的 200 响应。书源常用 `if (res.includes(...))` 判断，Dart 版要保留“返回字符串而非抛异常”。
4. **ajax 用书源主域 cookie**（按 `source.getKey()` 的 eTLD+1），即使请求的是别的域名；ajax 不补全相对 URL；URL 选项 `type` 会让 ajax 返回 hex。
5. **响应编码不看 URL 选项 charset**，只看 Content-Type 与 HTML meta。
6. **java.get/post/head 是 Jsoup 直连**：不带书源 header/cookie、不跟随重定向、≥400 抛异常、30s 超时，返回对象要模拟 Jsoup `Connection.Response` 的 `body()/header()/headers()/cookies()/statusCode()/url()`。
7. **getElement(s) 返回 Jsoup Element/Elements**，JS 会直接调 Jsoup API（`.text() .attr() .select() .html() .outerHtml()`）。Dart 侧需要一套兼容 Jsoup 的元素包装。getElement 在 CSS/XPath 模式实际返回列表。
8. **Rhino 字符串是 Java 对象**：`typeof` 为 object，有 `.equals()/.length()/.getBytes()` 等 Java 方法。QuickJS 下返回原生字符串，依赖 Java String 方法的书源会坏（建议对 3310 个书源静态扫描 `.equals(`、`.length()`、`.getBytes(`、`.isEmpty()` 等）；`java.lang.*`、`Packages.cn.hutool.*`（Hutool 5.8.22 仍在 classpath 供书源直接调用，`app/build.gradle.kts:258-259`）这类反射调用无法移植。
9. **byte[] 为有符号**，跨 JS 边界要统一（Uint8Array 与 Int8 语义的差异）。
10. **Base64 两套解码器**：无 flags 的 `base64Decode` 宽容（Hutool），带 flags 的和 `base64DecodeToByteArray` 严格（Android）；`base64DecodeToByteArray` 空串返回 null。
11. **AES 密钥长度不规整**：非 16/24/32 字节在 encrypt/decrypt 时抛；DES/DESede 只截断不补齐；不支持 ZeroPadding；ECB 忽略 IV；`decrypt(String)` 自动 hex/base64 识别存在误判。
12. **旧 API 的 bug 要原样复刻**：`aesEncodeToString` 实际在解密；`aesEncodeArgsBase64Str` 不解 Base64；`tripleDESDecodeArgsBase64Str` 的 iv 不解 Base64；`aesBase64DecodeTo*` 与 `aesDecodeTo*` 完全相同。
13. **timeFormatUTC 的偏移量单位是毫秒**；timeFormat 用设备时区（Dart 要用本地时区而不是 UTC）。
14. **encodeURI 是表单编码**（空格变 `+`），Dart 的 `Uri.encodeComponent` 不等价。
15. **toNumChapter 会丢掉“第…章”之外的文字**，无法解析时产生 `第-1章`。
16. **cache.get 内存命中忽略过期**；`saveTime*1000` Int 溢出（大于约 24.8 天的过期时间会算错）；`cache.put` 存对象会变成 `[object Object]`；byte[] 存到了另一个存储。
17. **cookie 按 eTLD+1 归一**，非 http 前缀的字符串原样当 key；`getCookie` 超 4096 字符时随机删键并持久化删除；`cookieToMap` 丢弃空值键；`setCookie` 覆盖而 `replaceCookie` 合并。
18. **登录信息加密密钥 = androidId 前 16 字节**：数据不可跨设备迁移；Dart 版应换成自己的设备密钥，迁移导入的 `userInfo_*` 无法解密，需让用户重新填写。
19. **source.getVariable 先读临时变量**（发现页设置），再读持久值。
20. `NativeBaseSource`/`ReadOnlyJavaObject` 隐藏 setter：`chapter.title = x` 在 Rhino 中静默无效，QuickJS 版如果开放写入，行为会变。
21. `webView` 的 `cacheFirst` 被忽略；`startBrowserAwait` 无总超时且全局串行。

---

## 10. 按 Android 依赖程度分级（Dart 版处理建议）

| 等级 | API | Dart 建议 |
|---|---|---|
| **必须 UI / 人工交互** | `startBrowser`、`startBrowserAwait`、`getVerificationCode`、`openUrl`、`toast`、`longToast` | 交互类走 Flutter 层回调（内置 WebView 页 / 验证码对话框），无 UI 宿主时抛明确错误；toast 无 UI 时降级为日志 |
| **必须 WebView 引擎** | `webView`、`webViewGetSource`、`webViewGetOverrideUrl`、URL 选项 `webView:true`/`webJs`、规则 `@webjs:`、`getWebViewUA` | 有 `flutter_inappwebview` 一类的 headless WebView 时实现；否则抛“需要 WebView”；`getWebViewUA` 可返回固定的移动端 UA |
| **设备标识** | `androidId`、`getLoginInfo/putLoginInfo` 的加密密钥 | 生成并持久化一个应用级随机 ID 代替；登录信息改用自有密钥 |
| **WebView Cookie 联动** | `cookie.removeCookie` 中清 WebView cookie | 有 WebView 时同步清除，否则忽略 |
| **App 配置** | `getReadBookConfig*`、`getThemeMode`、`getThemeConfig*` | 映射到 Dart 自己的配置或返回空 JSON |
| **调试 UI** | `log` 输出到调试台 | 接入 Dart 版调试会话；无会话时只写日志 |
| **纯逻辑，可完全移植** | 编码/摘要/加解密、`timeFormat*`、`encodeURI`、`t2s/s2t`（需找等价词典，并复刻排除词表）、`toNumChapter`、`randomUUID`、`put/get`、`cache.*`、`cookie.*`（需 PSL 库算 eTLD+1）、`ajax/connect/ajaxAll`、`get/post/head`、文件类（换成应用缓存目录并保留越界检查）、`queryTTF` | 按本文语义实现 |
