# source-js Specification

## Purpose

执行 Legado 书源里的 JS：规则、URL、请求头、`jsLib`、登录检查和目录后处理里的代码，按 legado-with-MD3（commit `d1b488b`）的语义求值，把结果交回规则引擎。MD3 用 Rhino，本能力用 quickjs-ng；两者在语言层面的差异只在下面写明的地方保留或放弃。

## Requirements

### Requirement: 规则里的 JS 段
规则按 `<js>…</js>`（非贪婪）和 `@js:`（一直到规则末尾）切成若干段，不区分大小写。各段 SHALL 组成管道：普通规则段照常取值，JS 段以上一段的输出作为 `result` 求值，返回值作为这一段的输出。规则第一段就是 JS 时，`result` 是当前内容。JS 段的代码在求值前 SHALL 先做和普通规则相同的文本处理：`@get:{键}` 换成变量值，`{{…}}` 先求值再拼回代码（内容以 `@`、`$.`、`$[`、`//` 开头时按规则取值，否则按 JS 求值），正则 AllInOne 结果上的 `$1`…`$99` 换成对应分组；代码末尾的 `##正则##替换` 不属于 JS，SHALL 在求值后作用于结果。

#### Scenario: 规则后接 JS
- **WHEN** 书名规则是 `tag.h1@text@js:result.trim() + '!'`，`h1` 的文本是 ` 三体 `
- **THEN** 结果为 `三体!`

#### Scenario: JS 代码里的内嵌规则
- **WHEN** 内容是 `{"id":7}`，规则是 `@js:'/book/' + {{$.id}} * 2`
- **THEN** 结果为 `/book/14`

#### Scenario: JS 后面的替换
- **WHEN** 规则是 `@js:result##\s+##`，`result` 是 `a b`
- **THEN** 结果为 `ab`

### Requirement: 求值作用域
每次求值 SHALL 使用一个新的变量层，注入本次的变量；顶层的 `var`、函数声明和未声明的赋值 MUST 只留在本次求值里，下一次求值读不到。顶层 `this` SHALL 是这个变量层，`this.java`、`this.result` 等可用。代码 SHALL 以非严格模式执行。求值结果是代码最后一个表达式语句的值。

#### Scenario: 顶层变量不泄漏
- **WHEN** 同一个书源先求值 `var x = 1; leaked = 2; x`，再求值 `typeof x + ',' + typeof leaked`
- **THEN** 第一次结果为 `1`，第二次结果为 `undefined,undefined`

#### Scenario: 非严格模式
- **WHEN** 求值 `for (i in [1,2]) {}; i`
- **THEN** 结果为 `1`，不报错

### Requirement: jsLib
书源的 `jsLib` 是代码时，SHALL 在第一次用到时执行一次，它的顶层声明对该书源的所有 JS 求值可见；jsLib 里的函数修改自己的顶层变量后，后续求值 SHALL 看到修改后的值。规则代码给 jsLib 里已有的名字赋值时，MUST 只遮蔽本次求值里的这个名字，不改 jsLib 的值。jsLib 里的函数以 `f()` 形式被调用时，函数内的 `this` SHALL 是调用方本次的变量层。jsLib 文本完全相同的书源 MAY 共用同一份 jsLib 状态。jsLib 执行出错时，该书源的每次 JS 求值 MUST 以带有原因的错误结束。jsLib 是 JSON 对象（按地址引用外部脚本）时，MUST 以「不支持的 jsLib 形式」错误结束。

#### Scenario: jsLib 的函数和状态
- **WHEN** jsLib 是 `var n = 0; function inc() { return ++n; }`，同一个书源先后求值 `inc()` 两次
- **THEN** 结果依次为 `1`、`2`

#### Scenario: 通过 this 取调用方变量
- **WHEN** jsLib 是 `function r() { return this.result + '!'; }`，规则求值 `r()`，`result` 是 `a`
- **THEN** 结果为 `a!`

### Requirement: 注入变量
规则里的 JS SHALL 注入：`java`（规则上下文的宿主对象）、`result`、`baseUrl`（当前页面地址）、`src`（当前内容）、`book`（搜索列表阶段是当前结果项，详情、目录、正文阶段是书籍）、`chapter` 和 `title`（目录项和正文阶段的当前章节及其章节名）、`nextChapterUrl`（正文阶段）、`source`、`cookie`、`cache`。URL 里的 JS SHALL 注入：`java`（URL 上下文的宿主对象）、`baseUrl`、`key`、`page`、`book`（搜索时为 null）、`source`、`result`、`cookie`、`cache`，MUST NOT 注入 `chapter`、`title`、`src`。书源级 JS（书源 `header`）SHALL 注入 `java`（书源本身）、`source`、`baseUrl`（书源地址）、`cookie`、`cache`。阶段里没有的对象注入为 null。

#### Scenario: 正文阶段的章节名
- **WHEN** 正文规则是 `@js:title + '\n' + result`，当前章节名是 `第一章`
- **THEN** 结果以 `第一章` 开头

#### Scenario: URL 里没有 chapter
- **WHEN** 章节地址模板里求值 `typeof chapter`
- **THEN** 结果为 `undefined`

### Requirement: 书籍、章节和书源对象
`book`、`chapter`、`source` SHALL 以对象形式提供 MD3 bean 的同名属性（如 `book.name`、`book.author`、`book.bookUrl`、`book.durChapterTitle`、`chapter.title`、`chapter.index`、`source.bookSourceUrl`、`source.bookSourceComment`）和下面「宿主 API」里列出的方法。Rhino 把无参 getter 当成同名属性，所以 `source` 还 SHALL 有 `key`（书源地址，同 `getKey()`）和 `tag`（书源名，同 `getTag()`）。给 `book` 的属性赋值 SHALL 写回书籍并随链路结果返回；给 `chapter`、`source` 的属性赋值 MUST 被忽略，属性值不变。

#### Scenario: 修改书名
- **WHEN** 详情的简介规则里执行 `book.name = '新名'; result`
- **THEN** 详情链路返回的书名是 `新名`

#### Scenario: 章节只读
- **WHEN** 目录项规则里执行 `chapter.title = 'x'; chapter.title`
- **THEN** 结果是原来的章节名

#### Scenario: 书源的 key 和 tag
- **WHEN** 书源地址是 `https://www.a.com`、书源名是 `测试源`，搜索地址里执行 `source.key + source.tag`
- **THEN** 结果是 `https://www.a.com测试源`

### Requirement: 值转换
JS 返回值交给规则引擎时 SHALL 按下面的规则转换：字符串原样；`undefined` 和 null 为 null；布尔转 `true`/`false`；数组转列表，元素各自转换；普通对象转键值对象；元素包装对象转回对应的元素或元素列表。数字转字符串时，整数值输出不带小数点的整数（`2`），其余按 JS 的数字格式（`2.5`）。转字符串时 null 的去向取决于进入点：规则取字符串时为空串；URL 的 `{{}}` 为空串；URL 的 `@js:`、`<js>`、`bodyJs` 和书源 `header` 的 JS 为字符串 `null`；URL 选项 `js` 和 `formatJs` 返回 null 时保持原值不变。规则取字符串时，返回值是数组或对象则按 JS 的 `String()` 转换（数组为逗号连接，对象为 `[object Object]`）。规则取字符串列表时，返回字符串按换行切开，返回数组直接作为列表，其他类型为空列表。规则取元素列表时，返回数组作为元素列表，返回 null 为空列表，其他类型 MUST 以错误结束。

#### Scenario: 整数不带小数点
- **WHEN** 字数规则是 `@js:1+1`
- **THEN** 结果为 `2`

#### Scenario: JS 返回对象列表作为结果项
- **WHEN** 搜索列表规则是 `@js:[{name:'三体',url:'/b/1'}]`，书名规则是 `name`，地址规则是 `url`
- **THEN** 得到一项，书名为 `三体`，地址为 `/b/1` 转成的绝对地址

#### Scenario: URL 里 @js 返回 null
- **WHEN** 搜索地址是 `@js:null`
- **THEN** 请求地址按字符串 `null` 处理

### Requirement: result 是元素或结构化值
当前内容是 HTML 元素时，注入的 `result`、`src` SHALL 是元素包装对象；是 JSONPath 取到的对象或数组时，SHALL 是对应的 JS 对象或数组；是正则 AllInOne 的分组列表时，SHALL 是字符串数组。宿主交给 JS 的列表（数组）SHALL 另外提供 `toArray()`、`size()`、`get(i)`、`isEmpty()` 方法，和 Java 列表的写法兼容。

#### Scenario: result 是元素
- **WHEN** 搜索列表规则是 `class.item`，书名规则是 `@js:result.select('h3').text()`
- **THEN** 书名为每一项 `h3` 的文本

#### Scenario: result 是 JSON 对象
- **WHEN** 列表规则是 `$.list[*]`，作者规则是 `@js:result.author + '著'`
- **THEN** 作者为每一项 `author` 字段加「著」

### Requirement: 求值的错误与取消
JS 抛出异常时，求值 SHALL 以 JS 错误结束，错误里带有 JS 的错误消息、书源名和出错的字段；错误是否让整条链路失败，按 book-chains 里各字段的错误处理规则决定（与 A 类规则出错时相同）。任务被取消或超过截止时间时，正在执行的 JS MUST 被中止，JS 的 `try/catch` MUST NOT 能拦住，包括阻塞在网络请求里的 JS。嵌套求值（JS 调用回调规则，回调规则里又有 JS）超过 10 层时 MUST 以错误结束，且 JS 的 `try/catch` 拦不住。

#### Scenario: JS 语法错误
- **WHEN** 目录章节名规则是 `@js:result.(`
- **THEN** 目录链路以 JS 错误结束，错误里有书源名和 `ruleToc.chapterName`

#### Scenario: 死循环被取消
- **WHEN** 正文规则是 `@js:try { while (true) {} } catch (e) {}`，任务被取消
- **THEN** 提交方收到取消错误，worker 之后仍可执行任务

### Requirement: Rhino 专有写法
书源 JS 执行之前，`=>` 前面紧挨着的数组字面量（`[a,b]=>`，Rhino 当成解构参数）SHALL 被加上括号（`([a,b])=>`）再执行；字符串、模板字符串、注释和正则字面量里的内容 MUST NOT 被改动，下标访问（`a[0]`）MUST NOT 被当成解构参数。

全局的 `java`、`javax`、`org` 和 `Packages` SHALL 是 Java 包对象：`org.jsoup.Jsoup`、`org.jsoup.parser.Parser`（以及 `Packages.org.jsoup…`）按 source-js-api「Jsoup」提供；`Packages.io.legado.app.help.http.StrResponse` 按「StrResponse 构造」提供；`java.lang.String`、`java.security.MessageDigest`（以及 `Packages.java…`）按「Java 字符串与摘要」提供；`java.io.ByteArrayOutputStream`、`java.util.ArrayList`（以及 `Packages.java…`）按「Java 内存字节流与列表」提供。调用或 `new` 其它类时 MUST 以「不支持的宿主 API：类名」结束，JS 的 try/catch 拦不住。包对象在 jsLib 的顶层和函数词法作用域里 SHALL 可用；规则、URL、书源变量层注入的 `java` SHALL 遮蔽全局包，仍是各自的宿主对象，jsLib 函数的 `this.java` SHALL 取调用方的宿主对象。目录 `formatJs` 不注入宿主 `java`，仍可访问全局 Java 包。

`JavaImporter(包…)` 和实例的 `importPackage(包…)` SHALL 支持导入已实现包中的类，在 `with` 中按短类名访问，普通变量继续沿外层作用域解析；类内静态方法和子包 MUST NOT 被当作导入类。`java.util.Base64`、`Arrays` 和 `javax.crypto` 的有限 AES 类按 source-js-api「Java Base64、数组与 AES」提供。`java.security.KeyFactory`、`Signature` 和 `java.security.spec.PKCS8EncodedKeySpec` 按「Java RSA 私钥与签名」提供。

其余依赖 Rhino Java 互操作的写法（全局 `importPackage`、任意 JVM 类、Java 字符串方法如 `.length()`、`.equals()`）不在支持范围，MUST 以错误结束，MUST NOT 被静默改写成别的语义。宿主 API 返回的字符串 SHALL 是 JS 原生字符串（MD3 里是 Java 字符串对象），`===` 比较和 `replaceAll` 按 JS 语义；Java 字符串包装只用于显式调用或构造 `java.lang.String` 的值。

#### Scenario: jsLib 的 java 与规则宿主分离
- **WHEN** jsLib 函数用 `java.security.MessageDigest` 和 `new java.lang.String(s).getBytes("UTF-8")` 算签名，并调用 `this.java.md5Encode(s)`
- **THEN** 两者得到相同的 MD5；规则里的 `java` 仍保留原有宿主方法，不新增 `lang` 或 `security` 属性

#### Scenario: 解构箭头函数
- **WHEN** 规则是 `@js:[["男频","1"],["女频","2"]].map([t,id]=>t+id).join(",")`
- **THEN** 结果是 `男频1,女频2`

#### Scenario: 字符串里的不改
- **WHEN** 规则是 `@js:"[a]=>" + [1][0]`
- **THEN** 结果是 `[a]=>1`

#### Scenario: jsLib 里用 Jsoup
- **WHEN** jsLib 是 `function first(h) { const { Packages } = this; return Packages.org.jsoup.Jsoup.parse(h).select("p").first().text(); }`，规则求值 `first("<p>甲</p>")`
- **THEN** 结果是 `甲`

#### Scenario: 使用 Packages
- **WHEN** 规则是 `@js:Packages.java.lang.System.currentTimeMillis()`
- **THEN** 以「不支持的宿主 API：Packages.java.lang.System.currentTimeMillis」错误结束
