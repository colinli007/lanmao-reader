## MODIFIED Requirements

### Requirement: Rhino 专有写法
书源 JS 执行之前，`=>` 前面紧挨着的数组字面量（`[a,b]=>`，Rhino 当成解构参数）SHALL 被加上括号（`([a,b])=>`）再执行；字符串、模板字符串、注释和正则字面量里的内容 MUST NOT 被改动，下标访问（`a[0]`）MUST NOT 被当成解构参数。

全局的 `java`、`javax`、`org` 和 `Packages` SHALL 是 Java 包对象：`org.jsoup.Jsoup`、`org.jsoup.parser.Parser`（以及 `Packages.org.jsoup…`）按 source-js-api「Jsoup」提供；`Packages.io.legado.app.help.http.StrResponse` 按「StrResponse 构造」提供；`java.lang.String`、`java.security.MessageDigest`（以及 `Packages.java…`）按「Java 字符串与摘要」提供；`java.io.ByteArrayOutputStream`、`java.util.ArrayList`（以及 `Packages.java…`）按「Java 内存字节流与列表」提供。调用或 `new` 其它类路径时，按 MD3 运行时有没有这个包区分（路径去掉开头的 `Packages.` 再看包根）：包根是 `java`、`javax`、`android`、`androidx`、`dalvik`、`kotlin`、`kotlinx`、`okhttp3`、`okio`、`cn.hutool`、`me.ag2s`、`io.legado`、`org.apache`、`org.jsoup`、`org.json`、`org.mozilla`、`org.w3c`、`org.xml`、`com.google`、`com.jayway`、`com.script` 的，MUST 以「不支持的宿主 API：类名」结束，JS 的 try/catch 拦不住；其它包根（MD3 里也没有，如改版阅读的 `io.legato.kazusa`）MUST 和 Rhino 一样以 JS 的 TypeError 结束，try/catch 可以捕获。包对象在 jsLib 的顶层和函数词法作用域里 SHALL 可用；规则、URL、书源变量层注入的 `java` SHALL 遮蔽全局包，仍是各自的宿主对象，jsLib 函数的 `this.java` SHALL 取调用方的宿主对象。目录 `formatJs` 不注入宿主 `java`，仍可访问全局 Java 包。

`JavaImporter(包…)` 和实例的 `importPackage(包…)` SHALL 支持导入已实现包中的类，在 `with` 中按短类名访问，普通变量继续沿外层作用域解析；类内静态方法和子包 MUST NOT 被当作导入类。实例的 `importClass(类…)` SHALL 按短类名（类路径的最后一段）登记导入的类，在 `with` 中可以访问：已实现的类导入后照常使用；未实现的类路径照样登记，调用或 `new` 时按上一段的规则结束。`importClass` 的参数是已实现的包（如 `java.util`）或不是 Java 包对象时 MUST 以 JS 错误结束。`java.util.Base64`、`Arrays` 和 `javax.crypto` 的有限 AES 类按 source-js-api「Java Base64、数组与 AES」提供。`java.security.KeyFactory`、`Signature` 和 `java.security.spec.PKCS8EncodedKeySpec` 按「Java RSA 私钥与签名」提供。

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

#### Scenario: importClass 导入已实现的类
- **WHEN** 规则是 `@js:var ji = new JavaImporter(); ji.importClass(Packages.java.util.ArrayList); with (ji) { var l = new ArrayList(); l.add("甲"); l.size() }`
- **THEN** 结果是 `1`

#### Scenario: importClass 导入未实现的类
- **WHEN** jsLib 顶层执行 `var ji = new JavaImporter(); ji.importClass(Packages.okhttp3.HttpUrl);`，规则在 `with (ji)` 里调用 `HttpUrl.parse("https://a.com")`
- **THEN** jsLib 正常加载；规则以「不支持的宿主 API：Packages.okhttp3.HttpUrl.parse」错误结束

#### Scenario: MD3 里没有的类可以捕获
- **WHEN** 规则是 `@js:try { new Packages.io.legato.kazusa.utils.TimeoutCancellationException(""); "改版" } catch (e) { "官方" }`
- **THEN** 结果是 `官方`
