## 1. 隔离求值与 jsLib（quickjs_ng_ffi）

- [x] 1.1 C 胶水新增变量层和隔离求值（D1、D10）：`qjs_layer_new` / `qjs_layer_free`、`qjs_eval_scoped`，预置非严格模式的 `__run`（`with` + 直接 eval，eval 后把新增的全局属性移到变量层），宿主回调增加「不可捕获的错误」返回状态（D9）；更新头文件，用 ffigen 重新生成绑定，Dart 侧加对应封装。验证：`js_engine_test.dart` 新增 js-engine 规格「声明不泄漏」「变量层上的变量」「复用变量层」三个场景，以及宿主函数返回不可捕获错误时外层 `try/catch` 拦不住，全部通过。
- [x] 1.2 jsLib realm（D2、D10）：`qjs_lib_new` / `qjs_lib_free` 在同一运行时里新建 JSContext 执行代码并 `preventExtensions`，主 realm 里用 Proxy 挂到变量层原型上。验证：js-engine 规格「共享作用域只读遮蔽」场景通过；另测 jsLib 函数 `f()` 调用时 `this` 是变量层、jsLib 里的死循环能被中止标志打断、释放后再用以错误结束。
- [x] 1.3 隔离求值的开销实测（风险第 1 条）：在 macOS 上连续做 2000 次隔离求值（每次注入 5 个变量、代码是 `result.trim()` 这类短表达式），记录总耗时。验证：数字写进 `packages/quickjs_ng_ffi/README.md`；超过 1 秒时停下来评估快路径方案。

## 2. 编码、加解密、时间与文本

- [x] 2.1 oracle（D12）：`tool/jsoup_oracle` 下新增 Java 程序，用 JDK（JCA、`URLEncoder`、`SimpleDateFormat`）、Hutool 5.8.22（宽松 Base64）和 AOSP 的 `android.util.Base64` 源码生成期望值，覆盖 AES/DES/DESede 的 ECB/CBC/PKCS5/NoPadding、错误密钥长度和错误填充、MD5/SHA/HMAC、Base64 各 flags 与非法输入、多字符集的表单编码、固定时区的日期格式。验证：生成的 fixtures 提交到 `test/fixtures/`，README 写明运行方法和依赖版本。
- [x] 2.2 编码：宽松和严格两套 Base64（含 Android flags）、hex、`strToBytes` / `bytesToStr`、`encodeURI`（表单编码，UTF-8/GBK/GB2312/GB18030/ISO-8859-1），字节数组用 -128 到 127 表示。验证：2.1 的编码类 fixtures 全部通过。
- [x] 2.3 加解密：加入 `pointycastle` 4.0.0（D11）；摘要、HMAC、`createSymmetricCrypto` 及其对象方法（密钥截断、AES 长度检查推迟到首次使用、ECB 忽略 IV、`decrypt` 的 hex/Base64 自动识别），旧版便捷函数按 `research/md3-host-api.md` 6.4 节照实现（含两处 bug）。验证：2.1 的加解密 fixtures 全部通过，source-js-api 规格「AES 默认 ECB」「旧函数的 bug 照旧」场景通过。
- [x] 2.4 时间与文本：`timeFormat`（本地时区）、`timeFormatUTC`（毫秒偏移，`SimpleDateFormat` 常用字母和单引号转义）、`toNumChapter`（含中文数字、全角数字、无法解析得到 `第-1章`）、`randomUUID`。验证：2.1 的日期 fixtures 通过；「UTC 偏移按毫秒」「中文章节号」场景通过；`toNumChapter` 另有 10 个手写用例（按 research 的语义，不拷贝 MD3 源码）。

## 3. 主 isolate 上的书源级状态

- [x] 3.1 `SourceStore` 与新宿主请求（D8）：内存键值表（带过期时间），覆盖缓存、书源变量、登录头、登录信息；`RuleHost` 处理 `store`、`log` 请求，构造时接收日志接收函数；Cookie 的读、写、合并、删除也走 `store`。验证：`host_test.dart` 新增用例：过期、`saveTime` 为 0 不过期、`replaceCookie` 合并而 `setCookie` 覆盖、非 http 地址原样作键、日志带书源地址到达接收函数。
- [x] 3.2 直连请求与响应补充：`HttpRequest` 增加「直连」选项（不带 Cookie 和书源请求头、不跟随重定向、默认超时 30 秒、状态码 ≥400 报错）和单次请求超时；`HttpResult` 增加 Set-Cookie 原始列表。验证：本地 HTTP 服务器的用例覆盖 302 不跟随、403 报错、Set-Cookie 含逗号日期时逐条保留。
- [x] 3.3 `RuleEnvironment` 增加 `store`、`log`：`WorkerRuleEnvironment` 走宿主请求，测试用的 Fake 和 Replay 环境挂内存 `SourceStore`；登录头在每个任务第一次构造请求时取一次，任务内写入时同步更新。验证：`dart analyze` 无问题，现有 538 个测试仍然通过。

## 4. JS 运行时（source-js）

- [x] 4.1 运行时骨架（D3、D5、D6）：每个 worker 一个引擎；预置 JS（三种 `java` 对象、`cookie`、`cache`、宿主列表的 `toArray` / `size` / `get` / `isEmpty`）；求值帧栈和 `__host.call` 分发；嵌套超过 10 层的错误；`evalRule` / `evalUrl` / `evalSource` / `evalFormat` 入口；JS 值到 Dart 的转换（整数不带小数点，各进入点的 null 去向）。验证：source-js 规格「求值作用域」「值转换」「求值的错误与取消」的场景作为单测通过（不起 worker）。
- [x] 4.2 jsLib：按 MD5 缓存最多 16 个 realm，执行出错不缓存，JSON 形式以「不支持的 jsLib 形式」结束。验证：「jsLib」要求的两个场景通过；另测出错后每次求值都报同一错误、第 17 个 jsLib 淘汰最早的。
- [x] 4.3 句柄表与包装对象（D4、D7）：任务级句柄表，`JsElement` / `JsElements` / `JsResponse` / `JsCipher` 包装类和 `toJSON` 标记，任务结束清空，失效句柄报错。元素方法复用 `html/` 下的 jsoup 语义。验证：source-js-api「元素包装对象」「响应对象」场景通过；另测元素作为 JS 返回值交回 Dart 后能继续用规则取值。
- [x] 4.4 `book`、`chapter`、`source` 对象：字段快照、`book` 的 setter 写回、`chapter` 和 `source` 赋值被忽略、各阶段的注入（搜索列表阶段 `book` 是当前结果项，URL 里没有 `chapter`）。验证：source-js「注入变量」「书籍、章节和书源对象」的场景通过。

## 5. 宿主 API（source-js-api）

- [x] 5.1 注册表与上下文：三种 `java` 对象各自暴露的方法，调用不存在的方法报 JS 错误；不支持的宿主 API 统一以 `UnsupportedHostApiException`（带 API 名、书源名、字段）结束。验证：「三种 java 对象」「不支持的宿主 API」场景通过，规格列出的不支持 API 逐个有用例。
- [x] 5.2 变量：规则、URL、书源三种 `put` / `get` 的写入顺序和保留键，`@put` / `@get` 与 `java.put` / `java.get` 同一份数据，`put` 的值为 null 报错；`source`、`book`、`chapter` 的变量方法，`setReverseToc`、`upCustomIntro`。验证：「变量读写」「书籍和章节的方法」场景通过。
- [x] 5.3 网络：`ajax`（URL 规则、书源域名 Cookie、不补全相对地址、数组取第一个、`type` 返回 hex、出错返回描述文本）、`ajaxAll`、`connect`（出错返回伪造的 200）、`get` / `post` / `head`（直连）、`getStrResponse`、`headerMap`。验证：本地 HTTP 服务器上「ajax 与 ajaxAll」「connect 与直连请求」的场景通过，另测阻塞在 `ajax` 里的 JS 被取消后 `try/catch` 拦不住。
- [x] 5.4 回调规则：`getString` / `getStringList` / `getElement` / `getElements` / `setContent`，不传内容时用当前内容。验证：「回调规则」场景通过；`setContent` 之后同一详情页的后续字段在新内容上取值。
- [x] 5.5 编码、加解密、时间、文本 API 接到 JS（第 2 组的实现）。验证：「编码」「摘要与加解密」「时间与文本」规格里的场景以 JS 调用的形式通过，字节数组能在 JS 和宿主之间往返。
- [x] 5.6 日志、Cookie、缓存、书源登录信息 API。验证：「日志与提示」「Cookie」「缓存」「书源对象的方法」场景通过；跨 worker 读缓存的场景在 `WorkerPool` 上通过。

## 6. 接入规则引擎

- [x] 6.1 `rule/analyze_rule.dart`：JS 段求值、`makeUpRule` 里的 `{{JS}}`、`result` 的四种形态（字符串、元素、JSON 值、分组列表）、JS 对象内容的快速路径、`getString` / `getStringList` / `getElements` 的返回值转换；去掉这里的 `NeedsJsException`，`@webjs:` 仍报「需要 WebView」。验证：source-js「规则里的 JS 段」「result 是元素或结构化值」场景和 rule-syntax 修改后的「变量与内嵌规则」「需要 WebView 时明确报错」场景通过；原有测试全部通过。
- [x] 6.2 `request/analyze_url.dart`：URL 里的 `@js:` / `<js>`（`@result` 替换）、`{{}}` 一律按 JS、`js` 和 `bodyJs` 选项、书源 `header` 的 JS（出错只记日志）、登录头叠加顺序。验证：source-request 修改后的「URL 模板」「URL 选项」「请求头」场景通过。
- [x] 6.3 `chain/chains.dart`：`loginCheckJs`（返回值不是响应对象时报错）、`formatJs`（共用变量层、`gInt` 累积、单章出错只记日志）、各字段的 JS 错误按现有的字段错误规则处理。验证：「登录检查 JS」「目录的 formatJs」和 book-chains 修改后的「链路在 worker 中执行」场景通过。
- [x] 6.4 更新调用方：spike、`tool/smoke.dart`（失败原因归类加上 JS 错误和不支持的宿主 API）、导出的 API。验证：spike 和 rule_engine 的 `dart analyze` 无问题，`dart test` 全部通过。

## 7. 真实书源验证

- [x] 7.1 联网冒烟：按 source-check 的 B、C 清单各跑一遍（全量或随机 200 个），统计四条链路成功数和失败原因；JS 错误和不支持的宿主 API 两类失败逐个排查，引擎问题当场修复并补用例。验证：结果写进选型文档；JS 错误类的失败都有结论（引擎问题已修，或注明是书源或网站的原因）。
- [x] 7.2 固定样例：从跑通的书源里录制至少 6 个，覆盖规则 JS、URL JS、`java.ajax`、加解密、`eval(source.bookSourceComment)` 或 jsLib、`formatJs` 或 `loginCheckJs`（能找到的话）；补上人工核对的 `expected`。验证：`recorded_test.dart` 不联网重放全部通过；找不到的覆盖项在任务描述里注明。（已录 6 个：规则 JS、URL 里的 `{{}}` 和 JS、`java.ajax`、`java.put/get`、`java.getString`、`java.base64Decode`、`java.timeFormat`。没有覆盖：加解密——跑通的两个用加解密的书源（UC 小说、阅友）在请求地址里带当前时间和签名，无法重放；jsLib、`eval(source.bookSourceComment)`、`formatJs`、`loginCheckJs`——跑通的书源里没有用到。这几项由单元测试覆盖。）
- [x] 7.3 大目录耗时：用一个每章都有 JS 的目录（上千章）测目录链路耗时。验证：数字写进 README；超过 2 秒时按风险第 1、2 条评估快路径。

## 8. spike 与文档

- [x] 8.1 spike 新增一项验证：在 worker 池里对一个 C 类书源（用到 `java.ajax` 或加解密）跑四条链路。验证：macOS、Android 模拟器和 iOS 模拟器（debug 构建）上全部验证项通过；真机 profile 构建推迟到所有功能开发完成后统一测试。
- [x] 8.2 文档：rule_engine README 补上 JS 部分和偏离表（D13），quickjs_ng_ffi README 补上新接口，选型文档更新规则引擎进度和冒烟结果。验证：三份文档已更新，`openspec validate add-js-runtime --strict` 通过。
