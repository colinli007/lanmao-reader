## Context

- Java 包对象在 `prelude.dart` 的 `javaPackage(path, known, isClass)` 里实现：`Proxy` 包一个函数，`known` 里有的属性返回实现，没有的返回下一层包代理（`known` 为 null）；`apply`、`construct` 一律 `hostCall('unsupported', [path])`，Dart 抛 `UnsupportedHostApiException`，JS 的 try/catch 拦不住。代理登记在 `javaPackages`（WeakMap，代理 → `{path, known, isClass}`）。
- 已实现的类有两种写法：一种是 `isClass` 为 true 的包代理（`Base64`、`Arrays`、`Cipher`、`MessageDigest`、`KeyFactory`、`Signature`、`Jsoup`、`Parser`），另一种是普通函数（`JavaString`、`ArrayList`、`ByteArrayOutputStream`、`SecretKeySpec`、`IvParameterSpec`、`PKCS8EncodedKeySpec`、`strResponse`），作为 `known` 的值挂在包上。路径有的带 `Packages.` 前缀（`Packages.java`、`Packages.io…`），有的不带。
- `JavaImporter` 只有 `importPackage`：登记包，`with` 里按短类名在已登记包的 `known` 里找，只返回类（不返回子包）。
- 「不支持的宿主 API」名单（`unsupported`）挂在 `javaObject` 上，三种 java 对象和书源对象都有；`common` 是它们共有的已实现方法。
- 书源级存储：worker 里经 `task.storeGet`/`storePut` 读写，主 isolate 上的 `SourceStore` 只有一份，app 用 `PersistentSourceStore` 落盘到数据库。`cache.put` 的键是书源 JS 给的原文，没有前缀；书源变量用 `v_<书源>_` 前缀。
- 分类书籍页（`explore_books_page.dart`）：一页里没有新书就算到底，底部按 `_books.isEmpty` 显示「没有书」或「没有更多了」。

## Goals / Non-Goals

**Goals：**
- 大灰狼聚合这类书源的 jsLib 能加载，发现和搜索不再因为这三处失败。
- MD3 里也会失败的写法和 MD3 一样能被书源捕获；MD3 能做而我们做不到的，仍然清楚地报「不支持的宿主 API」。
- 分类第一页为空时，提示把最可能的原因告诉用户。

**Non-Goals：**
- 全局的 `importClass`、`importPackage`（Rhino 顶层函数），现在不支持，这次也不做。
- 让网站拦截的书源能用（要 WebView）。
- `java.net.URL`、`okhttp3.HttpUrl` 等类的实现。大灰狼的 jsLib 只在个别函数里用到它们，发现和搜索走不到。

## Decisions

### D1 importClass：按短类名登记，已实现的类用注册表取名

Rhino 的 `importClass(类)` 把类按短类名加进导入器。我们要从传进来的对象知道它的类名：

- 包代理：`javaPackages` 里有路径，取最后一段。`known` 不为 null 且不是类（已实现的包，如 `java.util`）时抛 TypeError，和 Rhino 拒绝包一样。`known` 为 null 的代理（没实现的路径）无法区分是类还是包，按类登记：调用或 `new` 时才按 D2 结束，和「引用不报错、使用才报」的现有规则一致。
- 普通函数实现的类：`javaPackage` 建包时，把 `known` 里不是包代理的值登记到一个 WeakMap（值 → 属性名），`importClass` 从这里取名。这样在一个地方登记，不用逐个类改。
- 都不是：抛 TypeError。

导入器的查找顺序：先找 `importClass` 登记的类，再找 `importPackage` 登记的包，和 Rhino 一样，显式导入的类优先。

为什么不在 catch 里改 `java.log` 的行为：`java.log` 在 jsLib 词法作用域里是 Java 包，这是 MD3 的作用域语义（source-js「Rhino 专有写法」已经写明）。书源走进这个 catch 是因为前面的 `importClass` 失败了，MD3 上根本走不到这里，根因是缺 `importClass`。

### D2 Java 类路径按 MD3 有没有这个包根，决定可以捕获还是拦不住

「不支持的宿主 API」拦不住，是为了告诉用户「MD3 能做、我们还不能做」，不让书源的 try/catch 把能力缺口吞掉（add-rhino-compat D3）。所以判断依据是「这个类在 MD3 的运行时里存不存在」。

我们拿不到 MD3 完整的类表，用包根近似：路径去掉 `Packages.` 前缀后，以下面这些开头的视为 MD3 里存在：

- JDK 和 Android：`java`、`javax`、`android`、`androidx`、`dalvik`、`org.w3c`、`org.xml`、`org.json`
- Kotlin：`kotlin`、`kotlinx`
- MD3 带的库：`okhttp3`、`okio`、`org.jsoup`、`org.mozilla`、`org.apache`（Android 自带的 HTTP 客户端、commons-text）、`com.google`（Gson 等）、`com.jayway`（JsonPath）、`cn.hutool`、`me.ag2s`、`com.script`
- MD3 自己：`io.legado`

在这些包根下的，照旧 `hostCall('unsupported')`；不在的，抛 TypeError（消息写明类路径），和 Rhino 调用一个不存在的 Java 类（实际是 `NativeJavaPackage`）一样。

两种做法比较过：
- 全部改成可以捕获：最简单，但 MD3 里有、我们没实现的类会被书源的 catch 吞掉，书源走上和 MD3 不同的分支，书源校验也看不出缺的是哪个类。不选。
- 按包根区分：近似「MD3 里有没有」。名单漏掉某个 MD3 带的库时，后果是书源的 catch 接住、走降级分支，不会崩。选这个。

### D3 androidId：随机生成一次，存进书源级存储

MD3 返回 `Settings.Secure.ANDROID_ID`，书源拿它当设备号（签名、服务器登记）或判断平台。要的是「同一台设备上稳定」，不需要真的读设备。

- 实现在 `host_api.dart`：先 `storeGet('app.androidId')`，没有时用 `Random.secure()` 生成 8 字节，转成 16 位小写十六进制，`storePut`（不过期），再返回。
- 键用 `app.androidId`：不属于任何书源，不带 `v_` 前缀，和书源变量分开。`cache.put` 的键是书源给的原文，理论上可能写到同一个键，书源一般不会用这个名字。
- 从 `unsupported` 名单移到 `common`，三种 java 对象和书源对象都有，和 MD3 的 `JsExtensions` 一致。

### D4 分类第一页为空的提示

第一页解析出 0 本，几乎都是网站返回了验证页、错误页，或者规则和现在的页面对不上（这次排查的所有空分类都是这样），分类真的没书很少。提示改成「没有取到书，可能是网站拦截了请求，或者书源规则已经失效」，只改文案，判断条件不变（`_books.isEmpty` 且到底）。翻页后为空仍然是「没有更多了」。

## Risks / Trade-offs

- **包根名单不全**：MD3 带的某个库不在名单里时，调用它的书源会被自己的 catch 接住，走降级分支，而不是报「不支持」。影响是诊断信息少一点，不会更差。
- **androidId 第一次生成有竞争**：两个 worker 同时第一次调用时，可能各自生成一个，后写的覆盖先写的，先调用的那个书源这一次拿到的值和以后不同。只发生在第一次，影响是服务器那边可能多登记一次设备，不处理。
- **importClass 把没实现的包当成类**：`importClass(Packages.foo.bar)` 里 `foo.bar` 其实是包时，Rhino 会报错，我们照样登记。只在书源写错时才有差别。
