# Legado MD3（d1b488b）书源 JS 执行模型：Dart/quickjs-ng 移植须知

路径缩写：`R/` = `modules/rhino/src/main/java/com/script/`，`A/` = `app/src/main/java/io/legado/app/`。
标「实测」的结论来自 `scratchpad/jsprobe/Probe*.java`：用仓库里残留的 `modules/rhino/lib/rhino-1.7.14.jar`，按 MD3 的 ContextFactory 配置（ES6、解释模式、开启 JAVA_MAP_ACCESS）复刻后跑出来的。注意，实际打包用的是 **Rhino 1.8.1**（`gradle/libs.versions.toml:71,241`，`modules/rhino/build.gradle.kts:37`），这个 jar 没有被任何 gradle 文件引用。凡是标了「实测(1.7.14)」的条目，都要到真机 1.8.1 上再确认一遍。

---

## 0. 引擎配置总览

- 进程内只有一个全局 `ContextFactory`（`R/rhino/RhinoScriptEngine.kt:319-391`），配置为：`VERSION_ES6`（:323）、解释模式（:324）、`RhinoClassShutter`（:325）、`RhinoWrapFactory`（:326）、`instructionObserverThreshold = 10000`（:327）、`maximumInterpreterStackDepth = 1000`（:328）、`FEATURE_ENABLE_JAVA_MAP_ACCESS = true`（:335）。其余 feature 都用默认值：没开 DYNAMIC_SCOPE、没开 STRICT_MODE，也没开 ENHANCED_JAVA_ACCESS。
- 实际执行脚本的只有两个入口：`RhinoScriptEngine.eval(String, Scriptable, CoroutineContext?)`（:88-125）和 `RhinoCompiledScript.eval`（`R/rhino/RhinoCompiledScript.kt:57-87`），后者只有 `AnalyzeRule` 在用，并按 jsStr 缓存 16 条编译结果（`A/model/analyzeRule/AnalyzeRule.kt:865-869`）。
- 每次求值都会 `recursiveCount++`，嵌套达到 10 层时抛 `RhinoRecursionError`（`R/rhino/RhinoContext.kt:24-29`、`R/rhino/RhinoErrors.kt:5`）。这个计数是**每线程**的，所以 JS 调 `java.getString('@js:..')`，内层再嵌套，也算在这 10 层里。

---

## 1. JS 进入点全集与注入变量

### 1.1 规则里的 JS：`AnalyzeRule.evalJS`（`java` = 当前 AnalyzeRule 实例）

- 绑定（`AnalyzeRule.kt:833-847`）：`java`=this，`cookie`=CookieStore，`cache`=CacheManager，`source`，`book`=`ruleData as? BaseBook`，`result`，`baseUrl`，`chapter`，`title`=`chapter?.title`，`src`=`content`（当前 AnalyzeRule 的 content），`nextChapterUrl`，`rssArticle`=`ruleData as? RssArticle`，`fromBookInfo`。
- 什么时候当 JS：
  - `<js>…</js>`（非贪婪）和 `@js:…`（一直吃到规则末尾），正则不区分大小写（`A/constant/AppPattern.kt:5-6`）。`splitSourceRule` 用它把规则切成段：JS 段之前的文字照常当规则，JS 段拿上一段的输出作为 `result`（`AnalyzeRule.kt:553-562`，执行在 :248/:342/:402/:439）。
  - `{{…}}`（规则内，正则 `\{\{[\w\W]*?\}\}`，非贪婪，`AnalyzeRule.kt:956-957`）：内容以 `@`、`$.`、`$[`、`//` 开头时**当规则**，用 `this.content` 而不是当前 `result` 去求（:782-787，:739-743）。其他情况一律当 JS，`result` 等于当前结果（:745）。
  - 规则里只要有 `{{}}` 或 `@get:{}`，并且第一处出现的位置是 0，或者它前面没有 `##`，这条 SourceRule 就被改成 `Mode.Regex`（:649-657）。到了 getString 里，Regex 模式落进 `else -> rule`，也就是**直接返回拼好的模板字符串**（:351）。换句话说，`{{}}` 在规则里是模板，不是选择器的后缀。
  - `@webjs:` 在 WebView 里执行，不走 Rhino（`AppPattern.kt:7-8`，`AnalyzeRule.kt:173-188`），可以不管。
- `result` 在不同链路节点的取值：
  - 列表规则：页面 body 字符串。
  - 字段规则：当前 item。jsoup Element 包成 Java 对象；JSONPath 节点是 Java Map/List；正则 AllInOne 是 `List<String>`；JS 列表的元素是 NativeObject。
  - 字段规则串联时：上一段的输出，可能是 String、`List<String>`，或者 JS 返回的任何值。
- `book` 的取值：搜索/发现的列表规则阶段，ruleData 是 `RuleData`，`book` 为 null。逐 item 执行时会 `setRuleData(searchBook)`，`book` 就是**当前 SearchBook**（`A/model/webBook/BookList.kt:216-217`）。详情、目录、正文阶段是 `Book`。
- `chapter` / `title`：目录 item 阶段是新建的 BookChapter（`BookChapterList.kt:233-237`），`title` 在章节名规则求值时还是空串，等到 url 规则时已经有值。正文阶段是当前章节（`BookContent.kt:83,248`）。
- `nextChapterUrl` 只在正文阶段有值（`BookContent.kt:84`）。
- `baseUrl`：页面 URL，即 `setBaseUrl(res.url / redirect)`；正文阶段是章节绝对 URL。

### 1.2 URL 里的 JS：`AnalyzeUrl.evalJS`（`java` = AnalyzeUrl 实例）

- 绑定（`AnalyzeUrl.kt:364-377`）：`java`、`baseUrl`、`cookie`、`cache`、`page`(Int?)、`key`、`speakText`、`speakSpeed`、`book`=`ruleData as? Book`、`source`、`result`、`infoMap`。**没有 `chapter`、`title`、`src`**。正文 URL 虽然传了 chapter（`WebBook.kt:420-427`），JS 里也读不到，只能通过 `java.get('title')` 和 `java.put` 间接拿到（:389-408）。搜索时 ruleData 是 RuleData，所以 `book` 为 null。
- 执行顺序（`initUrl`，:148-156）：
  1. `analyzeJs`：`<js>` / `@js:` 按顺序执行，`result` 是到目前为止的 URL 文本。JS 段之间的普通文字里，`@result` 会被替换成上一个结果（:161-183）。每段结果都调 `.toString()`（:172），所以 **null 变成 "null"，Double 1 变成 "1.0"**。
  2. `{{…}}`：用 `RuleAnalyzer.innerRule("{{","}}")` 找**第一个** `}}`，不做配对（`RuleAnalyzer.kt:339-357`）。**一律当 JS，没有 isRule 判定**，`result` 为 null（`AnalyzeUrl.kt:193-199`）。null 变成 ""；整数值的 Double 用 `String.format("%.0f")`，没指定 Locale；其余用 `toString()`。如果替换后整条 URL 为空串，就保留原 ruleUrl（:201）。
  3. 替换 `<p1,p2>` 页码（:204-213）。
  4. 用 `\s*,\s*(?=\{)` 切出 URL 选项 JSON（:776）。选项里的 `"js"` 求值时 `result` 是绝对 url，返回值 `?.toString()` 后作为新 url；返回 null 则 url 不变（:258-262）。常见写法是在里面 `java.headerMap.put(..)` 改请求头。
  5. 选项 `"bodyJs"`：只在非 WebView 的 HTTP 响应之后执行，`result` 是 body，返回值 `.toString()`，**null 会变成 "null"**（:503-506）。`webJs` 在 WebView 里跑，不是 Rhino。
- 每 new 一次 AnalyzeUrl，都会在 `runScriptWithContext(coroutineContext)` 里重新算一遍请求头（:132-134），所以 header 的 JS 也是**每次请求都执行**。

### 1.3 书源对象上的 JS：`BaseSource.evalJS`（`java` = source 自身）

- 默认绑定（`A/data/entities/BaseSource.kt:333-351`）：`java`=source，`source`=source，`baseUrl`=`getKey()`（bookSourceUrl），`cookie`，`cache`，外加调用方用 `bindingsConfig` 追加的变量。**不传 coroutineContext**（:342、:350），能否取消完全取决于外层有没有套 `runScriptWithContext`。
- `header`：以 `@js:`（不区分大小写）或 `<js>` 开头时当 JS 执行，结果 `.toString()` 后按 JSON 解析成 Map。出错只记 AppLog，请求头为空，之后照常补默认 UA（:102-131）。
- `loginUrl`：`getLoginJs()` 只认**区分大小写**的 `@js:` / `<js>`，否则整段都当 JS（:70-78）。`login()` 会在它后面拼 `login.apply(this)`（:84-97）。
- `loginUi`：`@js:` / `<js>` 开头时，前面拼上 loginJs 再执行，绑定 `result`=空 Map、`book`=null、`chapter`=null（:179-203）。
- `exploreUrl`：以 `<js>` / `@js:`（不区分大小写）开头时，`evalJS` 额外绑定 `infoMap`，结果 `.toString().trim()` 后**落盘缓存**（`A/help/source/BookSourceExtensions.kt:64-80`）。出错会生成一条 `ERROR:` 分类，不会抛异常。
- `coverDecodeJs` 和 `ruleContent.imageDecode`：额外绑定 `book`、`result`=`ByteArray` 或 `InputStream`、`src`=图片 URL，**返回值必须是 Java `byte[]`**，否则 `as ByteArray` 失败，记 debug 日志并返回 null，图片加载失败（`A/utils/ImageUtils.kt:20-55`）。
- `callBackJs`（事件回调，带 `event`/`result`/`book`/`chapter`，有时 `java` 会被换成 SourceLoginJsExtensions）：`A/model/SourceCallBack.kt:59-70,95-107,119-130`。不属于 A 类链路。

### 1.4 其他字段

- `loginCheckJs`：在 `AnalyzeUrl.evalJS(checkJs, result = StrResponse)` 里执行，`java` = 本次请求的 AnalyzeUrl，**返回值被强转成 `StrResponse`**，返回别的类型就抛 ClassCastException，整条链失败（`A/model/webBook/WebBook.kt:73-77,126-130,173-177,211-215,270-274,348-352,433-437`）。
- `ruleToc.preUpdateJs`：`AnalyzeRule(book, source, preUpdateJs=true).evalJS(js)`，`result`/`src` 都为 null。只有在这个模式下才能调 `java.reGetBook()` 和 `java.refreshTocUrl()`（`WebBook.kt:303-315`，`AnalyzeRule.kt:913-952`）。
- `ruleToc.formatJs`：**单独的 ScriptBindings，所有章节共用**，绑定 `gInt`=0（只在开头设一次）、`index`（从 1 开始）、`chapter`、`title`。**没有 `java`、`source`、`book`，也不挂 jsLib**。返回值 `?.toString()` 后作为章节标题，返回 null 则标题不变；每章单独 try，失败只记日志（`BookChapterList.kt:141-158`）。因为 bindings 对象是同一个，**顶层 `var` 和 `gInt` 会在章节之间累积**。
- `ruleContent.replaceRegex`：不是 JS 字段，而是一整条规则，在外层 AnalyzeRule 上执行 `getString(replaceRegex, mContent = 全文)`（`BookContent.kt:190-195`）。规则可以写成 `##re##rep`，也可以带 `@js:`；JS 里 `result` 是拼好的全文，`src` 是第一页 body。
- `ruleContent.payAction`：`AnalyzeRule(book, source)` 先 `setBaseUrl(chapter.url)`、`setChapter(chapter)`，再 `evalJS(payAction).toString()`。结果是绝对 URL 就打开网页，是真值就刷新目录（`A/ui/book/read/ReadBookViewModel.kt:2561-2567`，`A/data/repository/manga/MangaReaderActionRepository.kt:238-251`）。这里 `content` 为 null，所以 `src` 为 null。
- `bookUrlPattern`：**不是 JS**，是 Kotlin 的整串匹配 `baseUrl.matches(it.toRegex())`，即 Java 正则（`BookList.kt:62-81`）。
- `ruleContent.webJs`、`sourceRegex`：WebView，不走 Rhino（`WebBook.kt:428-431`）。
- `ruleBookInfo.init`：通过 `getElement` 执行，返回值会成为新的 `content`，可能是 NativeObject（`BookInfo.kt:58-63`）。

---

## 2. 作用域

- **每次求值都会新建一个 ScriptBindings**（一个 `NativeObject`，`R/ScriptBindings.kt:7-46`）作为执行 scope，注入变量都是它的自有属性（`Context.javaToJS`，:27）。
- 没有 jsLib 时：`getRuntimeScope(bindings)` 每次给 bindings 设置一个**全新的** `cx.initStandardObjects()` 作为原型（`RhinoScriptEngine.kt:261-269`），内建对象互不相通。唯一例外是 `AnalyzeRule`：同一个实例 eval 超过 16 次后，会把那次的标准对象存进 `topScopeRef`，后续复用（`AnalyzeRule.kt:848-859`）。所以长列表后半段对内建对象的修改（比如 `String.prototype.x=`）会互相可见。
- 有 jsLib 时：`bindings.prototype = sharedScope`，`sharedScope.prototype` 是它自己那份标准对象（`AnalyzeRule.kt:855-858`，`AnalyzeUrl.kt:378-385`，`BaseSource.kt:342-349`）。同一个 jsLib 的所有求值共享这份内建对象。
- **顶层 `var`、函数声明和未声明的赋值都落在本次的 bindings 上，不会泄漏到下一次**（实测：第二个新 bindings 里 `typeof leaked` 为 `undefined`）。顶层给 jsLib 里已有的变量赋值，只会在本次 bindings 上新建一个同名属性遮蔽它，**不改共享值**（实测：`counter=100` 之后，jsLib 里的 `inc()` 仍从 3 开始数）。
- 顶层 `this` 就是本次的 bindings，所以 `this.java`、`this.result` 都能用（实测；`BaseSource.login` 里的 `login.apply(this)` 就依赖这一点，见 `BaseSource.kt:90`）。
- **SharedJsScope**（`A/model/SharedJsScope.kt`）：
  - 缓存 key 是 `MD5(jsLib 全文)`（:34），所以**jsLib 文本完全相同的不同书源会共用同一个 scope**。缓存是 `LruCache<String, WeakReference<Scriptable>>(16)`（:28），超出 LRU 容量或被 GC 回收后会重新执行 jsLib，**之前的状态会无预期地重置**。
  - jsLib 可以是 JSON 对象，判定只看去掉首尾空白后是否 `{…}`（`A/utils/StringExtensions.kt:57-61`）。这时**只执行值为绝对 URL 的项**：先下载，再以 MD5(url) 为 key 永久落盘到 ACache，执行顺序就是 JSON 里的书写顺序；**非 URL 的值直接忽略**；下载失败抛 `下载jsLib-…失败`（:40-67）。如果不是 JSON，就当普通 JS 执行（:68-70）。
  - jsLib 执行完之后调用 `scope.preventExtensions()`（:71-76）。效果：jsLib 里的函数做未声明赋值时会静默失败，再读这个变量就是 ReferenceError；**jsLib 顶层已有的 `var` 仍然可以被 jsLib 内的函数改写，而且改写在所有求值、所有线程之间共享**（实测：连续两次 `inc()` 分别得到 1、2）。帮助文档 `assets/web/help/md/ruleHelp.md:20-21` 说的「不可再赋值，抛密封异常」是上游 `sealObject` 的行为，**和 MD3 代码不一致**。
  - jsLib 执行出错时，`getScope` 会把异常抛出去，而且不缓存失败结果，所以这个书源之后的每次 evalJS 都会失败。缓存失效的入口：编辑书源时 jsLib 有变化（`BookSourceEditViewModel.kt:221`）、调用 `source.refreshJSLib()`（`BaseSource.kt:313-320`）。
  - **jsLib 函数是词法作用域**：函数体内找不到本次注入的 `result`/`book`/`source`，`java` 解析到的是 **Java 顶层包 `java`**（实测得到 `[JavaPackage java]`），所以 jsLib 里不能直接写 `java.ajax`。但从规则 JS 里以 `f()` 形式调用时，函数内的 `this` 就是本次 bindings（实测 `this.result`、`this.java` 都能取到）。jsLib 顶层代码执行时用的是一个空 bindings，同样没有任何注入变量。

---

## 3. 值转换（重点在 LiveConnect 差异）

### 3.1 JS 返回给 Kotlin

- `unwrapReturnValue`（`RhinoScriptEngine.kt:307-316`）：先解包 Wrapper（Java 对象），`ConsString` 转成 String，`undefined` 转成 null，**其他类型原样返回**，NativeArray、NativeObject、Double、Integer、Boolean 都不做处理。
- 数字（实测(1.7.14)）：字面量和算术结果是 `Double`，`1` 得到 1.0，`page+1` 得到 3.0，`parseInt('3')` 得到 3.0。来自 Java int 的值、字符串 `.length`、`JSON.parse` 出来的整数是 `Integer`。所以 Kotlin `toString()` 时：
  - 规则里的 `{{}}`：整数值的 Double 走 `%.0f`（Locale.ROOT）（`AnalyzeRule.kt:749-752`），URL 里的 `{{}}` 同理（`AnalyzeUrl.kt:197`）。
  - **`@js:` 作为 getString 规则、URL 里的 `@js:`、选项 js、bodyJs、header、exploreUrl、payAction、formatJs 都直接 `.toString()`**：`@js:1+1` 得到 `"2.0"`，而 `@js:result.length` 得到 `"11"`；`1e21` 得到 `"1.0E21"`（Kotlin 的格式，不是 JS 的）。
  - JS 列表元素是 NativeObject 时，字段取值走 `result[rule]?.toString()`（`AnalyzeRule.kt:327`）。实测：字面量 `{id:123}` 取 `id` 得到 `"123.0"`，`JSON.parse('{"id":123}')` 取 `id` 得到 `"123"`。
- `getString` 收尾（:360-375）：null 变成 `""`；其余 `toString()`，于是 NativeArray 会变成 `org.mozilla.javascript.NativeArray@hash`，NativeObject 变成 `[object Object]`，Java List 变成 `[a, b]`；只要字符串里有 `&` 就做 `unescapeHtml4`（正文传了 unescape=false 除外）；`isUrl` 时空串回退为 baseUrl，否则拼成绝对地址。
- `getStringList`（:267-284）：String 按 `\n` 切开；NativeArray 和 Java List 直接当 List；其他类型（Double、NativeObject）在 `as? List<String>` 处得到 null。
- `getElements`（:446-447）：`as List<Any>`。NativeArray 或 Java List 都可以；**返回字符串或对象会抛 ClassCastException**，返回 null 得到空列表。
- **NativeObject 快速路径**（:210-234、:314-330）：content 是 NativeObject 时**只用第一个 SourceRule**，同一条规则里后面的 `@js:` 段和串联段都会被忽略。模式可以是 Js、Json（JSONPath 直接作用在 NativeObject 这个 Map 上）、`{{}}` 模板，或者直接用 key 取值。content 是 Gson 的 `LinkedTreeMap` 时，干脆**拿原始规则串当 key**（:235-236、:331-332）。
- `getElement` 拿到 NativeObject 后用 `setContent` 设回去，这时 `isJSON` 等于 `"[object Object]".isJson()`，结果是 false（:101-104）。

### 3.2 Kotlin 注入 JS（`Context.javaToJS`）

- 注入的 `String`、`Number`、`Boolean` 会**变成 JS 原始值**（实测 `typeof result` 为 `"string"`，`typeof page` 为 `"number"`）。其他对象包成 `NativeJavaObject`；`byte[]` 等数组包成 `NativeJavaArray`（**元素是有符号 -128..127**）；null 就是 null（`typeof` 为 `"object"`）。
- 注入的 JS 字符串（如 `result`、`baseUrl`、`key`、`title`、`src`）上能用的方法（实测）：
  - `.equals()`、`.equalsIgnoreCase()` **可用**（Rhino NativeString 的非标准扩展）。
  - `.replaceAll()` 是 **JS ES2021 语义**：第一个参数按字面量处理，不是正则。
  - `.length()` 报 TypeError；`.matches()` 报找不到函数。
- **Java 方法和 bean getter 返回的 String 是被包装的 `java.lang.String`**：WrapFactory 默认 javaPrimitiveWrap=true，MD3 没改（`R/rhino/RhinoWrapFactory.kt:46-90`）。实测 `typeof java.ajax(u)` 为 `"object"`，`typeof book.name` 为 `"object"`。在这种值上：
  - `===` 和 JS 字符串比较得 **false**，`==` 得 true。
  - **优先调用 Java 方法**：`.length()` 能用，而 `.length` 是函数；`.split(s)` 是 **Java 正则语义**，返回 Java `String[]`；`.replaceAll`、`.replaceFirst`、`.matches` 也是 Java 正则；`.replace(/re/g, x)` 会抛**重载歧义 EvaluatorException**；`.trim`、`.indexOf`、`.substring` 都走 Java 实现。
  - Java 没有的方法会回退到 JS `String.prototype`，比如 `.match`、`.slice`、`.substr`。
  - `JSON.parse(x)`、`String(x)`、`x + ''` 都能正常转换。
  - 受影响的返回值：`java.ajax`、`java.getString`、`java.get`、`java.base64Decode` 一类、`cache.get`、`source.xxx`、`book.xxx`、`chapter.xxx`、`java.log(x)` 等。其中 `java.log(msg)` 原样返回参数（`A/help/JsExtensions.kt:1128-1135`），由于参数类型是 Any，返回的 JS 字符串**也会被包成 Java String**。
- Java List 和 Map（实测）：`list.length`、`list[0]` 可用；`forEach(lambda)` 可用（调的是 Java Iterable 的 forEach）；`.map()` 没有。`map.key`、`map['key']` 来自 JAVA_MAP_ACCESS，`.get()`、`.size()` 是 Java 方法。`JSON.stringify(javaMap/List)` 可用。JSONPath 规则的 item 就是 Java Map，书源常写 `result.get('x')`。
- bean 属性：Kotlin `var` 通过 getter/setter 暴露成属性，`book.name` 实际是 `getName()`。可写性（`A/App.kt:346-358`）：
  - `Book`、`SearchBook` 没有注册包装器，**可读可写**，`book.name='x'` 会真正调用 setter（实测）。
  - `BookChapter`、各类 Rule、`Book.ReadConfig` 用 `ReadOnlyJavaObject`：**赋值被静默忽略**；当 `xxx` 属性存在时，`setXxx` 方法会被隐藏成 undefined（`R/rhino/ReadOnlyJavaObject.kt:9-35`）。
  - `BookSource`、`RssSource`、`HttpTTS` 用 `NativeBaseSource`：只有 `variable` 能赋值，`setXxx` 同样被隐藏，`setVariable` 除外（`A/help/rhino/NativeBaseSource.kt:10-38`）。
- JS 传给 Java 参数（实测 + Kotlin 规则）：
  - 参数是 `String`：数字按 JS 规则转换，`1` 得到 `"1"`；undefined 得到 `"undefined"`；对象得到 `"[object Object]"`。
  - **参数是 Kotlin 非空 `String` 时传 null 会抛 NPE**（例如 `java.put(k, null)`），项目没有剥离参数断言（`app/proguard-rules.pro` 里没有相关规则）。
  - 参数是 `Any`：数字变成 `Double`，所以 `cache.put('k', 1)` 存进去的是 **"1.0"**（`A/help/CacheManager.kt:58-70`）；JS 对象变成 NativeObject，存成 `"[object Object]"`。
- 被 ClassShutter 拦下的对象（File、ClassLoader、Context 等），在 JS 里**直接拿到 null**（`RhinoWrapFactory.kt:56-58`，`R/rhino/RhinoClassShutter.kt:46-188`）。

### 3.3 只在 Rhino 下成立的写法

- 下面这些依赖 Java 互操作：
  - `Packages.x.y.Z`、`new JavaImporter(...)` 加 `with`：标准对象里就有（实测，`app/src/test/.../JsTest.kt:135-145`、`app/src/androidTest/.../AndroidJsTest.kt:15-50`）。
  - `importPackage`、`importClass` 在书源作用域里**不存在**：作用域原型是 `initStandardObjects()`，不是 ImporterTopLevel（实测 `typeof importPackage` 为 `undefined`）。它们只在 `RhinoScriptEngine.eval(String)` 走 ScriptContext 的那条路径里存在（:249-259）。
  - 在注入了 `java` 的作用域里，`java.lang.*` 不可用，因为 `java` 被注入对象遮蔽了，必须写 `Packages.java.lang.*`（`docs/dev/js.md:22`）。而在 jsLib 里 `java` **就是**这个 Java 包。
  - 直接调用 jsoup Element/Elements、okhttp/StrResponse（`.body()`、`.raw()`）、`Connection.Response`、hutool、javax.crypto、android.util.Base64 等 Java API。
- 下面这些是旧版 Rhino 语法（实测(1.7.14) 可用，quickjs 解析不了）：`for each (x in o)`、表达式闭包 `function(x) x*2`、不带 `*` 但用了 `yield` 的旧式生成器，还有 `toSource`、`uneval`、`getYear`、`String.prototype.trimLeft` 等非标准 API。

---

## 4. Rhino 版本与语言特性

- 实际版本是 **1.8.1**，`VERSION_ES6`，解释模式。文档里写的是 1.8.0（`docs/dev/js.md:5`）。
- 实测(1.7.14) **支持**：
  - 语法：`let`/`const`、箭头函数、模板字符串、解构、`function*`、rest 参数、`**`。
  - 内建对象：Promise、Symbol、Map/WeakMap、BigInt、`Object.entries`/`fromEntries`、`includes`、`padStart`、`at`、`flat`、`replaceAll`、`globalThis`。
  - 其他：`with`；正则的 `s`、`y` 标志。
- 实测(1.7.14) **不支持**：`class`、`async`/`await`、展开语法 `...`、默认参数、`?.`、`??`；正则的 `u` 标志、具名捕获组、后行断言；`Reflect`、`Proxy`；`console`、`setTimeout`、`atob`、`TextEncoder`、`print`。1.8.x 可能补上了其中一部分，**需要真机复核**。不过 quickjs 本身是超集，这对移植影响不大。
- 必须照顾的**语义差异**：
  - `for (let i…)` 循环里的闭包全部拿到最终值（实测 `3,3,3`）；`for (const x of …)` 直接报语法错。MD3 帮助文档也要求循环里改用 `var`（`assets/web/help/md/jsHelp.md:20`、`docs/dev/js.md:27`）。
  - 给 `const` 重新赋值会**被静默忽略**（实测）。
  - `new Date('2024-01-02 03:04:05')` 得到 NaN（实测）。
  - `sort((a,b)=>a>b)` 这种返回布尔值的比较器在 Rhino 里排得是对的。
  - Promise 回调不会在本次求值内同步执行。

---

## 5. 超时与中断

- **引擎层没有挂钟超时**。中断完全依赖协程取消：每执行 10000 条指令调一次 `observeInstructionCount`，再调 `RhinoContext.ensureActive()`（`RhinoScriptEngine.kt:327,340-344`，`RhinoContext.kt:16-22`）。检测到 Job 已取消就抛 `RhinoInterruptError`（继承自 Error，**JS 的 try/catch 捕获不到**），`superDoTopCall` 再把它还原成 `CancellationException` 抛出（:379-389）。
- 只有带 Job 的 coroutineContext 才会被采用（:95-97）。`AnalyzeRule` 的 context 来自 `setCoroutineContext`（`AnalyzeRule.kt:960-963`）。`BaseSource.evalJS` 不传 context，所以会**沿用外层 `runScriptWithContext` 设置的 context**（`R/rhino/RhinoExtensions.kt:68-90`），外层没设就**完全不可中断**，图片解密 JS 和 `formatJs` 都属于这种情况。
- 真正的超时来自上层：搜索每个源 30 秒（`A/domain/usecase/SearchBooksUseCase.kt:189`），换源 60 秒，缓存正文 30 秒（`A/model/CacheBook.kt:405`），书源校验时间可配置，`reGetBook` 是 30 分钟。
- 阻塞调用：`java.ajax`、`connect` 用 `runBlocking(coroutineContext)` 发请求，跟着父 Job 一起取消（`JsExtensions.kt:101-131,180-217`）。`ajax` 失败时**返回异常栈字符串，不抛异常**，只有取消时才会通过 `ensureActive` 抛出。
- 另外两条限制：JS 调用栈深度最多 1000，超出抛 `Exceeded maximum stack depth`，这个 JS 能捕获；嵌套 eval 最多 10 层，超出抛 RhinoRecursionError，这个 JS 捕获不到，Kotlin 的 `catch (e: Exception)` 也接不住。
- 每次进入脚本都要 `allowScriptRun=true`，否则拒绝执行（:98，:381-383），防的是绕开引擎入口直接回调 JS 函数。

---

## 6. 错误处理

- JS 异常的转换：`RhinoException` 转成 `ScriptException(msg, sourceName, line)`。`throw 'x'` 得到的 msg 是 `x`，其余异常得到 `re.toString()`。最终消息形如 `x in <Unknown source> at line number 1`（`RhinoScriptEngine.kt:106-115`，`R/ScriptException.kt`）。Java 方法抛出的异常会被包成 WrappedException，**JS 能 catch**。
- `AnalyzeRule` 和 `AnalyzeUrl` 本身**不捕获异常**，异常的去向由链路决定：
  - **搜索/发现列表**：列表规则、书名、作者、bookUrl 出错时，**整个源的结果都失败**；分类、字数、最新章节、简介、封面各自 try/catch，失败只写一条 Debug 日志，字段留空（`BookList.kt:220-281`）。
  - **详情**：init、书名、作者、tocUrl 出错会抛出；分类、字数、最新章节、简介、封面各自捕获（`BookInfo.kt:58-170`）。
  - **目录**：列表、章节名、url、isVolume、isVip、isPay、updateTime 都不捕获，出错就抛；nextTocUrl 也会抛；formatJs 按章捕获（`BookChapterList.kt:141-158,212-268`）。
  - **正文**：content 和 nextContentUrl 会抛；title 用 runCatching，只记日志（`BookContent.kt:167-170`）；replaceRegex 和 subContent 会抛。
  - **URL**：`@js:`、`{{}}`、选项 js 出错时 AnalyzeUrl 的构造直接抛异常，请求不会发出。header 的 JS 出错只记日志（`BaseSource.kt:119-121`）。
  - **其他**：preUpdateJs 记日志后返回 Result.failure，当 `runPerJs` 为真时会让目录获取失败（`WebBook.kt:303-329`）。loginCheckJs 返回的不是 StrResponse 时抛 ClassCastException。图片解密失败返回 null。jsLib 加载失败时该源的所有 JS 都失败。
- `RhinoRecursionError` 和 `RhinoInterruptError` 都继承自 Error，会穿过所有 `catch (e: Exception)`。

---

## 7. `java.getString` 等回调

- `java` 就是**当前执行链上的那个 AnalyzeRule 实例**。`java.getString(rule[, mContent[, isUrl]])` 在没传 mContent 时使用 `this.content`，也就是当前 item 或页面，**而不是 `result`**（`AnalyzeRule.kt:291-311`）。规则串可以写成任意完整规则，包括 `@js:`、`{{}}`、`##`、`@put`。嵌套 JS 会重新建 bindings，`java` 仍然是同一个实例，`result` 是 content。嵌套层数受第 0 节的 10 层限制。
- 模式判定用的 `isJSON` 取自 `this.content`，跟传入的 mContent 无关。此外 SourceRule 按规则串缓存在实例级的 `stringRuleCache` 里（:529-534），而 `setContent` **不清这个缓存**，所以同一条规则串的模式由第一次解析时的 content 决定。
- 能改变实例状态的调用：`java.setContent(x[, baseUrl])` 会**改掉这个实例的 content**，后续字段规则都受影响，比如详情页所有字段共用一个实例。`java.put`/`java.get` 的读写顺序是 chapter → book → ruleData → source（:801-827）；`java.get('bookName')`、`java.get('title')` 是特殊 key。
- 网络调用：`java.ajax(url)` 新建一个 AnalyzeUrl，`ruleData=book`，**URL 里的 JS 会再次执行**；url 参数可以是数组，这时只取第一个元素（:886-908）。`java.getElement`、`java.getElements` 返回 jsoup 或 Java 对象。
- 在 `AnalyzeUrl` 上（loginCheckJs 和 URL JS 里）：`java.initUrl()`、`java.getStrResponse()`、`java.headerMap`、`java.put`/`java.get` 都可用。`url` 只有 getter，赋值会失败。

---

## 8. 移植时容易出错的地方

1. **每次求值都要有独立的全局**：要能返回最后一个表达式语句的值（completion value），`var`、函数声明、未声明赋值都不能泄漏，顶层 `this` 等于 bindings 对象。在 quickjs 里如果直接 `JS_Eval` 到 globalThis，就会泄漏。可行做法：把 bindings 作为全局对象的原型或 `with` 目标，并把未声明赋值兜进本次对象，或者每次求值用独立的 JSContext。
2. **jsLib 共享 realm**：按 MD5(jsLib) 缓存，状态可以被函数改写；preventExtensions 的效果要保留；jsLib 函数看不到注入变量，`java` 是包对象；以 `f()` 调用时 `this` 是 bindings。另外，在 Rhino 里 jsLib 状态跨线程共享，移植后每个 isolate 各有一份，这一点无法对齐，要接受这个差异。
3. **数字转字符串**：哪条路径用 `%.0f`、哪条路径直接用 Kotlin `toString()`，要逐一照搬第 3.1 节。Rhino 里 Integer 和 Double 的区分取决于值的来源，quickjs 无法完全复现，**需要明确取舍**（建议保留 `"2.0"` 这类行为差异的记录，至少保证 `{{}}` 路径一致）。
4. **null 的去向**：URL `@js:`、bodyJs、header、payAction、exploreUrl 里会变成 **"null"**；getString 里变成 ""；URL `{{}}` 里变成 ""；选项 js 和 formatJs 里则保持原值不变。
5. **Java String 和 JS string 的二元性**：方法名相同时，语义取决于值从哪来（`replaceAll`、`split`、`length`、`===`）。如果要提供兼容垫片，`equals`、`equalsIgnoreCase`、`contains`、`isEmpty`、`matches`、`replaceFirst` 可以挂到 `String.prototype` 上，`length()` 没法做。Java Map/List 上的 `.get`、`.size` 要靠 Proxy 包装来兼容。
6. **`byte[]` 的约定**：图片解密 JS 必须返回 Java `byte[]`；字节在 Rhino 里是有符号的。
7. **`{{}}` 的判定**：规则里遇到 `@`、`$.`、`$[`、`//` 开头当规则，其余当 JS，整条规则被当作模板；URL 里**一律当 JS**，按第一个 `}}` 截断，不做括号配对。
8. **NativeObject 快速路径**只用第一个 SourceRule，Gson Map 直接拿原始规则串当 key。
9. **`book` 和 `chapter` 的可写性不同**：book 能写，chapter 和 source 的赋值被静默丢弃。
10. **结果的后处理**：getString 结果只要含 `&` 就做 HTML 反转义；isUrl 时还要转成绝对地址或回退为 baseUrl。
11. **中断语义**：取消必须让 JS 无法 catch。Rhino 没有挂钟超时，quickjs 用 interrupt handler 加截止时间，效果上会比 Rhino 更严格，这一条可以接受。
