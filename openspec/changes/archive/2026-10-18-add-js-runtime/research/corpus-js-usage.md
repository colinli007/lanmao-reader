# Legado 书源 JS 写法语料统计（B / C 级）

> 目的：为用 quickjs-ng（ES2023，无 Java 互操作）重写书源 JS 运行时提供数据。只读分析，脚本在 `scratchpad/corpus/`（`load.py`、`jsx.py`、`select.py`、`analyze.py`、`q7.py`、`extra.py`，用 `python3 -I` 运行）。

## 0. 口径

- 书源：`sources/sources/*.json` 共 3323 个不同的 `bookSourceUrl`。分级清单 B 859、C 538，其中 2 个 URL 在书源文件里找不到，**实际分析 B 858、C 538**。
- 同一个 URL 有多个不同版本（B 319 个、C 219 个）。每个 URL 选「静态抽出的宿主 API 集合和分级清单 `apis` 一致」的那个版本：1380/1396 完全一致，16 个不一致。不一致的原因是 API 藏在打包混淆代码或 `bookSourceComment` 里，或者清单把注释掉的 `//java.log` 也算进去了。
- JS 片段按 MD3 的实际求值点抽取：
  - `<js>…</js>`、`@js:…`（`AppPattern.JS_PATTERN`）。
  - `{{…}}`：URL 字段（searchUrl/exploreUrl）里全部算 JS；规则字段里排除 `isRule` 的情况（以 `@`、`$.`、`$[`、`//` 开头）。
  - 整段就是 JS 的字段：jsLib、loginCheckJs、coverDecodeJs、ruleToc.preUpdateJs/formatJs、ruleContent.callBackJs/imageDecode。
  - loginUrl、loginUi 的 action，以及 URL 选项里的 `"js"`/`"bodyJs"`。
  - `ruleContent.webJs`、`@webjs:` 和选项里的 `webJs` 是 WebView JS，单独计、不算 quickjs 负载。
- 求值前的预处理（和 MD3 一致）：
  - `<js>`/`@js:` 代码里的 `{{…}}` 先求值再做文本替换。
  - `@js:` 后面的 `##正则##替换` 不属于 JS。
  - 统计时注释、字符串和正则字面量先遮蔽，再匹配。
- 「平凡模板」指 `{{key}}`、`{{page}}`、`{{baseUrl}}`，项目里已经不经 JS 直接替换。**source-check 也不把它们算作 JS**：B、C 里只含平凡模板的书源都是 0 个。

---

## 1. JS 出现的字段和形式

### 1.1 按字段统计书源数（已排除平凡模板）

| 字段 | B（858） | B 形式 | C（538） | C 形式 |
|---|---|---|---|---|
| ruleSearch.* | 411 | `<js>` 215 / `@js:` 190 / `{{}}` 17 | 252 | `<js>` 137 / `@js:` 109 / `{{}}` 72 |
| ruleToc.* | 212 | `@js:` 152 / `<js>` 60 / `{{}}` 8 / 整段 1 | 290 | `@js:` 169 / `<js>` 105 / `{{}}` 69 / 整段 3 |
| ruleExplore.* | 204 | `@js:` 116 / `<js>` 90 / `{{}}` 2 | 107 | `@js:` 46 / `<js>` 45 / `{{}}` 45 / 选项 js 1 |
| ruleContent.* | 184 | `@js:` 104 / `<js>` 60 / `{{}}` 30 | 228 | `@js:` 132 / `<js>` 94 / `{{}}` 10 |
| ruleBookInfo.* | 171 | `@js:` 96 / `<js>` 45 / `{{}}` 44 | 245 | `<js>` 105 / `@js:` 105 / `{{}}` 90 |
| exploreUrl | 54 | `{{}}` 43 / `@js:` 8 / `<js>` 3 | 101 | `@js:` 44 / `{{}}` 41 / `<js>` 16 |
| searchUrl | 46 | `{{}}` 33 / `<js>` 7 / `@js:` 6 | 172 | `{{}}` 92 / `@js:` 71 / `<js>` 9 |
| header（`@js:`/`<js>`） | 20 | | 13 | |
| loginUrl（真正的登录 JS） | **≈0**（102 个非空，但都是 `{ "url": "null" }`、`｡◕‿◕｡` 这类占位文本） | | 9（另有 9 个占位文本） | |
| loginCheckJs | 0 | | 11 | |
| bookSourceComment / variableComment（被 `eval` 的代码） | 8 | | 9 | |
| jsLib | 1 | | 3 | |
| coverDecodeJs | 1 | | 0 | |
| loginUi（JS action） | 0 | | 1 | |
| ruleContent.webJs（WebView，不计入） | 见 D 级 | | | |

- 出现最多的具体字段：
  - B：searchUrl、exploreUrl（多数是平凡模板）；ruleSearch.coverUrl 286；ruleContent.content 147；ruleExplore.coverUrl 139；ruleSearch.bookUrl 88；ruleBookInfo.intro 84；ruleToc.nextTocUrl 70；ruleToc.chapterUrl 65。
  - C：ruleContent.content 209；ruleBookInfo.tocUrl 128；ruleToc.chapterUrl 126；ruleSearch.bookUrl 106；ruleToc.chapterList 102；ruleBookInfo.intro 81；ruleToc.updateTime 69。
- 规模：
  - 每个书源的 JS 总字符数，B 中位数 138、P90 410；C 中位数 367、P90 2946。
  - 每个书源的片段数，B 中位数 1、P90 4；C 中位数 3、P90 11。
  - 极端值来自内嵌的 CryptoJS 或打包混淆代码，单个书源最多 18.9 万字符。

### 1.2 B 级里「只有 `{{…}}`」的书源

- **72 个 B 级书源（8.4%）去掉占位用的 loginUrl 后没有任何 JS**。其中 56 个只有 loginUrl，16 个另有平凡模板。它们被判成 B 只是因为 loginUrl 非空，对四条阅读链路来说等同于 A 级。
- **B 级里全部 JS 都是非平凡 `{{…}}` 的：73 个（8.5%）**。
  - 只出现在 URL 模板（searchUrl/exploreUrl）里的：31 个（3.6%）。
  - 出现在规则字段里的：42 个。
- 这 73 个书源里的表达式（一个书源可以属于多类）：
  - page 算术：28 个，如 `{{page*2}}`、`{{(page-1)*20}}`、`{{page-1}}`。
  - 字符串字面量：28 个，如 `{{'\n'+'​'}}`、`{{'换源阅读🎭'}}`、`{{'&lrm;'}}`，多在 ruleBookInfo。
  - 读宿主对象属性：13 个，如 `{{chapter.title}}`、`{{book.name}}`、`{{book.durChapterTitle}}`、`{{source.key}}`。
  - 三元表达式：如 `{{page==1?'':'index_'+page+'.html'}}`，6 个。
  - 其它只有 5 处：`{{baseUrl.match(/(\d+)/)[1]}}`、`{{Math.floor(Math.random()*10000)+1}}`、`{{"《"+book.name+"》作者："+book.author}}`。
- 结论：B 级里「只要很小 JS 支持」的部分大约是 72 + 73 = 145 个（16.9%）。前 72 个不需要 JS；后 73 个只要表达式求值，再加上对 book/chapter/source 的只读属性。
- 全体 B 里含各类 `{{}}` 的书源数：平凡 784、page 算术 62、其它 97。

### 1.3 `<js>`/`@js:` 代码内部也有 `{{}}`（预处理语义）

- `<js>`/`@js:` 代码里含规则型 `{{$.id}}`、`{{@@text…}}` 的：B 14、C 79。MD3 先按规则取值，再把结果文本替换进 JS 源码，然后才 eval。
- 代码里含 JS 型 `{{…}}` 的：B 12、C 58。
- `@js:…##正则##替换` 这种 JS 后接正则替换的：B 18、C 14。
- JS 代码里用 `$1`/`$3` 正则组做文本替换的（AllInOne 正则规则后接 JS）：B 3、C 13。例如 `java.timeFormat($3)+"  "+$5+"字"`。
- 这些都是**求值前的文本预处理**，运行时必须在 eval 之前做，否则会出现语法错误或 `$` 未定义。

---

## 2. 注入变量的使用（书源数；排除平凡模板；去掉在片段内用 var/let/const 声明过的）

| 变量 | B | C | 说明 |
|---|---|---|---|
| result | 617 | 417 | 几乎都是 `result.match()`（B 295 / C 125）、`.replace()`（138 / 95）、`.split()`（46 / 19） |
| baseUrl | 141 | 200 | |
| key | 13 | 94 | 平凡 `{{key}}` 另计（B 780、C 524） |
| page | 90 | 85 | 平凡 `{{page}}` 另计 |
| book | 33 | 51 | 只读属性为主 |
| source | 29 | 123 | |
| chapter | 21 | 6 | |
| title | 10 | 35 | 正文规则里的 title/src/nextChapterUrl：B 6、C 14 |
| src | ≈19 | ≈23 | 含少量同名局部变量的误报 |
| nextChapterUrl | 2 | 0 | |
| java | 0（按定义） | 476 | |
| cookie | 0 | 74 | removeCookie 70 |
| cache | 0 | 5 | getFile/putFile 3、get 2、put 1 |
| infoMap | 0 | 2 | |
| rssArticle / fromBookInfo / speakText / speakSpeed | 0 | 0 | |

- `book.xxx` 的属性读取：
  - B：name 10、kind 6、totalChapterNum 5、bookUrl 4、tocUrl 2、origin 2、durChapterTitle 2、author 2、intro / coverUrl / canUpdate 各 1。
  - C：name 16、origin 13、intro 9、kind 8、durChapterTitle 7、author 4、canUpdate 2、type 2、coverUrl 1、variable 1。
  - C 的方法调用：upCustomIntro() 3、getVariable() 2。
- `chapter.xxx`：
  - B：title 16、index 5。
  - C：title 3、url 1。C 里的 nid、sort、chapter_name、wordCount 是同名局部 JSON 对象，不是注入的 chapter。
- `source.xxx`：
  - B 只读属性：bookSourceUrl 21、bookSourceComment 6、variableComment 1、key 1。
  - C 方法：getKey() 79、getVariable() 15、putLoginHeader() 12、getLoginInfoMap() 8、setVariable() 4、getLoginHeaderMap() 2、getLoginHeader() 1。
  - C 属性：bookSourceComment 9、bookSourceUrl 8、key 6、header 3。
- **result 的实际类型不只是字符串**，运行时要能给出不同的包装：
  - result 当 jsoup Element 用：B 14、C 7。例如 `result.select('em').hasClass('vip')`、`result.text()`、`result.parentNode()`、`result.attr('title')`。
  - result 当数组或 List 用：`result[i]` 有 B 27、C 17；`result.toArray()` 有 C 11。
  - result 当 JSON Map 读字段：B 6、C 4。例如 `result.pay_status`、`result.comic_id`。
  - `JSON.parse(result)`：B 29、C 43。

---

## 3. Rhino 专有写法（quickjs 下会失败或语义不同）

### B / C 级里基本没有，Java 互操作都已经被分到 D 级

| 写法 | B | C | 代表片段 |
|---|---|---|---|
| `.equals(` / `.equalsIgnoreCase(` / `.length()` / `.matches(` / `.contains(` / `.getBytes(` / `.replaceFirst(` | 0 | 0 | — |
| `.isEmpty()` | 0 | 1 | `var isVip = !java.getElements(rules.vip).isEmpty();` |
| `.replaceAll(` 字符串参数（Java 正则语义） | 0 | 4 | `….replaceAll('<style.*style>','').replaceAll('<([^<]*…`；`v = v.replaceAll("\\?", "a1a1")` |
| `String(x)` 包装 | **63** | **200** | `String(result).replace(/.*?(\d*?)(\d{1,3})\//,…)`；`sub=String(result).slice(1,-1).split(…)` |
| `Packages.` / `java.lang.` / `javax.` / `JavaImporter` / `importPackage` / `new java.` / `org.jsoup` / `android.` | 0 | 0 | — |
| E4X、`for each`、`.class`、`.getClass()` | 0 | 0 | — |
| `.size()` | 0 | 0 | — |
| `.get(i)`（不是 java/cache/source 的 get） | 0 | 1 | `con.k = n[i].select('a').get(0).text();` |
| jsoup `.text()` | 9 | 15 | `result.select('h2').text() +'：'+ result.text()` |
| jsoup `.attr(` | 2 | 24 | `java.getElements(".downfile a").toArray().map(a => '【'+a.text()+'】'+a.attr('href'))` |
| jsoup `.select(` / `.selectFirst(` | 11 | 12 | `$[i].select("a").forEach(a=>{ list.push({ text: a.te…` |
| jsoup `.ownText()` / `.html()` | 0 | 4 | `java.put("bookIntro",result[result.length-1].html())`；`intro=java.getElements('#intro').html()` |
| jsoup `.hasClass()` / `.parentNode()` | 8 / 5 | 7 / 0 | `((result.hasClass('isvip')) ? '🔒':'')+(result.text())` |
| 直接在 getElements/getElement 结果上调方法（`.toArray()` 为主） | 0 | **29** | `java.getElement("@@id.subFrom@input").toArray()`；`String(java.getElements(".btn@a.1").attr("href"))` |
| 响应对象的 Java 方法 `.body()` / `.headers()` / `.cookies()` / `.raw().request().url()` | 0 | **27** | `java.connect(url).raw().request().url()`；`java.post(url,body,head).headers()`；`java.head(baseUrl,{…}).cookies()` |
| `eval(` | 23 | 57 | 打包混淆 `eval(function(p,a,c,k,e,r){…})`，B 4、C 1；`eval(result.match(/(eval\([\s\S]+?)<\/script/)[1])` |
| `eval(String(source.bookSourceComment / variableComment))` | 7 | 9 | 把公共代码放在注释字段里再 eval，相当于穷人版 jsLib |

- 说明：
  - `String(x)` 在 ES 里合法。它在 Rhino 里的作用是把 `javaPrimitiveWrap` 包装出来的 java.lang.String 转成 JS 字符串。宿主直接返回 JS 字符串时，这个写法无害。
  - `.toArray()` 和 jsoup 方法是 B/C 级里**唯一成规模的 Java 对象依赖**。getElements/getElement 应返回带 `toArray()`、`text()`、`attr()`、`select()`、`html()`、`ownText()`、`hasClass()`、`parentNode()`、`get(i)`、`isEmpty()` 的 JS 包装对象。网络 API 的返回值要带 `body()`、`headers()`、`cookies()`、`code()`、`url()`、`raw()`。
  - `.replaceAll(字符串)` 的 4 处，语义取决于接收者：
    - 如果接收者是 JS 字符串，例如前面 `.replace()` 的结果，ES 的 replaceAll 按字面量替换。Rhino 1.8.1 应该也是这样（未核实），那么这些写法在 MD3 下可能本来就没生效。
    - 只有接收者是 Java String 时，才是 Java 正则语义。
    - 数量很少，可以不兼容。
  - 内嵌 CryptoJS（B 2、C 6）是纯 JS，quickjs 可以直接跑。
- **D 级对照**（398 个，每个 URL 取第一个版本）：

| 写法 | 书源数 |
|---|---|
| `org.jsoup` | 115 |
| `Packages.` | 44 |
| `importPackage` / `importClass` | 35 |
| `JavaImporter` + `with(javaImport)` | 31 |
| `.getBytes(` | 30 |
| `javax.` | 27 |
| `android.` | 21 |
| `.size()` | 17 |
| `.contains(` | 11 |
| `.length()` | 1 |
| E4X、`for each`、`.getClass()` | 0 |

  典型片段：`var key = SecretKeySpec(String("242ccb…").getBytes(),"AES")`。

---

## 4. ES 特性

| 特性 | B 书源 | C 书源 |
|---|---|---|
| 任一 ES6+ 语法 | 112（13.1%） | 173（32.2%） |
| 箭头函数 | 76 | 125 |
| 模板字符串 | 38 | 73 |
| let | 21 | 68 |
| const | 2 | 9 |
| 解构 | 0 | 3 |
| for…of | 0 | 2 |
| `?.` / `??` | 0 / 0 | 1 / 1 |
| padStart/padEnd | 0 | 6 |
| Array.from / includes / find | 17 | 19 |
| Map/Set | 0 | 1 |
| class、async/await、generator、Promise | **0** | **0** |
| fetch / setTimeout / TextEncoder / URLSearchParams | 0 | 0 |

- 大多数是 ES5 风格，Rhino 1.8.1 支持的 ES6 子集（let、箭头函数、模板字符串）用得不少。quickjs-ng 全部支持，**这一项没有兼容风险**。
- 要注意的反方向问题：大量代码依赖**非严格模式**，例如未声明变量直接赋值 `host = …`、`for (i in s)` 不写 var。D 级还用 `with(javaImport)`。运行时必须用 sloppy 模式执行脚本。

---

## 5. jsLib

| 级别 | 有 jsLib | 形式 | 大小（字节） |
|---|---|---|---|
| A | 0 | — | — |
| B | 1 | 代码 1 | 16184（favcomic，混淆代码） |
| C | 3 | 代码 3 | 146 / 1100 / 1150（towan 字数格式化、pad/formatDate、_0x 混淆 base64） |
| D | 12 | 代码 12 | 256 – 21478，中位数约 1.3K |

- 全部 3323 个 URL 里任一版本带 jsLib 的只有 18 个。**JSON（URL 映射）形式为 0**。
- D 级 jsLib 里出现 `const {java} = this` 和 `var java = this.java`。jsLib 里的函数通过 `this` 拿到调用方作用域里的 java、source、cookie，运行时要保证函数调用时的 `this` 是每次求值的 bindings 对象。
- MD3 语义：jsLib 只求值一次，作为共享原型作用域，然后调用 `preventExtensions`。每次规则求值都用新的 bindings 对象，原型指向它。

---

## 6. C 级宿主 API

### 6.1 频率和覆盖曲线

- C 级共用到 60 个不同的 API。
- 每个书源用到的 API 数：1 个的 217、2 个的 141、3 个的 90、4 个的 28、5 个的 26、6 个及以上的 36。

| 实现前 N 个 API | 全部 API 都被覆盖的 C 级书源 |
|---|---|
| 1 | 85（15.8%） |
| 3 | 142（26.4%） |
| **5** | **254（47.2%）** |
| **10** | **370（68.8%）** |
| 15 | 431（80.1%） |
| **20** | **465（86.4%）** |
| **30** | **499（92.8%）** |
| **40** | **517（96.1%）** |
| 50 | 528（98.1%） |
| 60 | 538（100%） |

- 前 20 个 API（括号里是使用书源数）：

| 名次 | API | 名次 | API |
|---|---|---|---|
| 1 | java.ajax 199 | 11 | java.getElements 31 |
| 2 | java.put 158 | 12 | java.aesBase64DecodeToString 24 |
| 3 | java.getString 139 | 13 | java.setContent 19 |
| 4 | java.get 120 | 14 | java.post 16 |
| 5 | java.timeFormat 102 | 15 | source.getVariable 15 |
| 6 | source.getKey 79 | 16 | java.getElement 14 |
| 7 | cookie.removeCookie 70 | 17 | java.getStringList 13 |
| 8 | java.base64Decode 43 | 18 | java.encodeURI 12 |
| 9 | java.log 43 | 19 | source.putLoginHeader 12 |
| 10 | java.md5Encode 34 | 20 | java.toNumChapter 12 |

- 第 21 到 30 名：source.getLoginInfoMap 8、java.toast 7、source.setVariable 7、java.longToast 6、java.head 6、java.connect 5、java.base64Encode 5、java.getVerificationCode 5、java.t2s 5、java.randomUUID 4。

### 6.2 按类别（使用该类 API 的 C 级书源数）

| 类别 | 书源数 | 类别 | 书源数 |
|---|---|---|---|
| Network | 217 | Codec | 60 |
| Variable | 181 | Crypto | 58 |
| RuleCallback | 165 | Log | 43 |
| BookContext | 108 | Text | 22 |
| Time | 106 | Ui | 18 |
| Cookie | 75 | Cache | 5 |

Font、File、Device 各 1 到 2 个。

### 6.3 不依赖 Android UI / WebView 的部分

- 完全不碰 Ui/WebView 类 API 的：**520 个（96.7%）**。再排除 Device、Font、File 类，还剩 517 个（96.1%）。
- 用到 Ui 类的 18 个里，大多数只是 toast（7）和 longToast（6），可以降级为日志或应用内提示。
- 真正离不开交互 UI 的只有 **7 个（1.3%）**：getVerificationCode 5、refreshExplore 2、getWebViewUA 1，有重叠。
- 同时排除 Network 和 RuleCallback 后，只用纯函数和变量类 API 的有 206 个（38.3%）。这部分可以最先打通。

---

## 7. 跨次求值的全局状态

- 检测方法：
  - 对每个书源，收集每个 JS 片段里声明或赋值的名字，包括 var/let/const/function、参数和隐式全局赋值。
  - 再找在另一个片段里只读不写的自由标识符。
  - jsLib、被 eval 的 comment 代码、loginUrl 到 loginUi 的拼接，都按 MD3 的语义排除。
- **结果：B、C 共 0 个确认案例。** 第一版有 6 个候选（UAA、看看阅读、读书阁等），复核后都是误报，分两种情况：
  - `@js:{{$.type}}=='2'` 里的 `{{}}` 预处理；
  - `@js:…##\${3,}##` 的正则尾巴。
- 这和 MD3 的实现一致：
  - `AnalyzeRule.evalJS` 和 `AnalyzeUrl.evalJS` 每次都新建 `ScriptBindings` 作为作用域。顶层 var/function 和隐式全局都落在这个对象上，下一次求值就没了。
  - 只有 jsLib 的共享作用域（已 preventExtensions）跨次存在。
- 书源实际用的跨规则状态机制：

| 机制 | B | C |
|---|---|---|
| `@put:{}` | 60 | 128 |
| `@get:{}` | 52 | 124 |
| `java.put` | 0 | 158 |
| `java.get` | 0 | 119 |
| source.setVariable / getVariable | 0 | 7 / 15 |
| book.putVariable / getVariable | 0 | 0 / 2 |
| cache.* | 0 | 5 |
| `this.x =` | 2 | 11 |
| 修改内置对象原型 | 0 | 0 |

- 结论：运行时可以「每次求值都用新的全局对象（或新的 bindings 层）+ 共享的 jsLib 层」。不需要支持跨求值的顶层变量持久化。

---

## 对运行时设计的直接含义（摘要）

1. **求值前预处理**是 B 级的大头：
   - `{{rule}}` 和 `@get:{}` 的文本替换、`$n` 正则组替换。
   - 切掉 `##…` 尾巴。
   - URL 里的 `{{expr}}` 求值。
2. **sloppy 模式**：要允许隐式全局，每次求值都用新的作用域。jsLib 作为共享的原型层。
3. **result 多态**：字符串、jsoup Element、List/数组、JSON Map 四种都要支持。Element 和 Elements 包装至少要有：

   | 对象 | 需要的方法 |
   |---|---|
   | Element / Elements 包装 | text、attr、select、selectFirst、html、ownText、hasClass、parentNode、get、toArray、isEmpty |
   | 网络响应对象 | body、headers、header、cookies、code、url、raw().request().url() |

4. Java 字符串方法、Packages、JavaImporter、E4X 在 B/C 级里**为 0**，不用模拟。`String(x)` 原生可用。
5. 宿主 API 实现前 20 个可以覆盖 C 级 86%，前 40 个覆盖 96%。Ui 类里只有 toast 需要降级，硬 UI 依赖只有 7 个书源。
