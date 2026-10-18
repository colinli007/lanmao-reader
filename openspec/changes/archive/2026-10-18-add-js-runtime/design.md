## Context

动机和范围见 proposal.md，行为要求见 specs/。MD3 的语义和书源语料的统计整理在 `research/` 下，实现时逐条对照：
- `research/md3-js-model.md`：JS 进入点、作用域、jsLib、值转换、错误与中断（附 `文件:行号`）；
- `research/md3-host-api.md`：宿主 API 的签名、返回值和怪异行为；
- `research/corpus-js-usage.md`：B、C 类书源实际怎么写 JS（字段分布、注入变量、Rhino 专有写法、宿主 API 覆盖曲线）。

这三份是读源码和静态扫描得出的；其中标「实测(1.7.14)」的条目用的是 MD3 仓库里残留的 Rhino 1.7.14，MD3 实际打包的是 1.8.1。探针和扫描脚本放在会话的临时目录，没有进仓库。

现状和约束：

- **quickjs_ng_ffi**：值跨 FFI 边界一律是 JSON 字符串，C 侧不暴露 JSValue；宿主函数按路径注册（如 `java.ajax`），参数和返回值都是 JSON；求值有外部中止标志和超时，中止能穿过宿主函数边界。
- **阻塞桥**：worker 里一次只执行一个任务，宿主函数通过 `WorkerContext.current` 取当前任务；`callHost` 同步等待主 isolate，可以在 JS 调用的宿主函数里嵌套使用（spike 已验证）。
- **rule_engine**：核心是同步代码，网络和取消从 `RuleEnvironment` 注入；需要 JS 的地方现在都抛 `NeedsJsException`（`rule/analyze_rule.dart` 的四个取值入口和 `_evalInner`，`request/analyze_url.dart` 的 URL、选项、请求头，`chain/chains.dart` 的 `formatJs`）。规则拆分已经完整移植了 MD3 的 `SourceRule`，包括 JS 段里的 `@get`、`{{}}`、`$n` 和 `##` 处理，JS 段只差最后的求值。
- **书源语料**（`research/corpus-js-usage.md`）：B、C 类里 Java 字符串方法、`Packages`、`JavaImporter` 都是 0，集中在 D 类；成规模的 Java 对象依赖只有元素对象上的 jsoup 方法和网络响应对象上的方法；没有书源依赖跨次求值的顶层变量；jsLib 只有 4 个，全是代码形式；ES 特性只用到箭头函数、模板字符串、`let`，但大量依赖非严格模式。

## Goals / Non-Goals

**Goals:**
- B 类和 C 类里只用到本次范围内宿主 API 的书源，在本引擎上的结果与 MD3 一致。
- 求值相互隔离，书源之间、任务之间不会通过 JS 全局状态互相影响。
- JS 和规则引擎的边界只有一处：所有进入 JS 的地方走同一个运行时入口，所有宿主 API 走同一套分发，不在各个取值入口里各写一份。
- 取消和截止时间对 JS 完全生效，包括阻塞在网络里的 JS 和嵌套求值。

**Non-Goals:**
- 不模拟 Rhino 的 Java 互操作（`Packages`、Java 字符串方法、Java 集合方法），只提供语料里成规模用到的元素对象和响应对象。
- 不复刻 Rhino 里 Integer 和 Double 的区别（D6）。
- 不做持久化：缓存、书源变量、登录头、登录信息都只在进程内存里，落盘交给后续的存储层。
- 不做发现页（`exploreUrl`、`ruleExplore`）、登录流程（`loginUrl`、`loginUi` 的执行）、图片解密（`coverDecodeJs`、`imageDecode`）、`callBackJs`、`payAction`、`preUpdateJs`：它们不属于四条链路，等对应功能做的时候再接。

## Decisions

### D1 隔离求值：同一个 JSContext 里，用 `with` + 直接 eval 建变量层

每个 worker 仍然只有一个引擎、一个 JSContext。每次求值时，由预置的 JS 包装函数执行：

```js
function __run(layer, code) {           // 非严格模式
  with (layer) { return eval(code); }   // 直接 eval
}
__run.call(layer, layer, code)
```

- 直接 eval 在函数里执行，代码里的 `var`、函数声明落在包装函数的变量环境里，`let`/`const` 落在 eval 自己的词法环境里，函数返回后都消失。
- 注入的变量是 `layer` 的属性，`with` 让代码按名字读写它们；顶层 `this` 是 `layer`。
- 未声明的赋值（`x = 1`，`layer` 上没有 `x`）会落到全局对象上。包装函数在 eval 前记下全局对象的属性名，eval 后把新增的属性移到 `layer` 上并从全局删除。新建的 `layer` 随后丢弃，等于不泄漏；`formatJs` 复用同一个 `layer`，这些赋值就留在它上面，与 MD3 一致。
- 包装函数的参数名不能被书源代码看到，所以用 `arguments[0]`、`arguments[1]` 取，不声明形参。
- jsLib 层：`layer` 的原型指向这个书源的 jsLib 作用域对象（D2），`with` 沿原型链查找，jsLib 的名字可见；给同名变量赋值时，普通赋值在 `layer` 上新建自有属性，只遮蔽不修改；从 `layer` 上找到的函数以 `f()` 调用时，`this` 是 `layer`。这三点正是 MD3 `bindings.prototype = sharedScope` 的效果。

C 胶水新增一个入口：调用引擎里预置的包装函数，把代码作为字符串参数直接传给它（不拼接进 JS 源码，避免转义）；变量层由 Dart 侧给出一个编号，JS 侧用编号在一个 Map 里取得 `layer` 对象，求值结束后由 Dart 决定是否释放这个编号。

**备选 A：每次求值新建一个 JSContext。** 内建对象也是新的，和 MD3 最像；但新建上下文要初始化全部内建对象，一个目录页可能有上千次求值（每章的章节名、地址各一次），开销不可忽略；跨上下文传递 jsLib 对象还会遇到 `instanceof Array` 这类跨 realm 问题。语料里没有书源修改内建对象原型，这一点隔离不需要。

**备选 B：直接在全局求值，结束后删掉新增的全局属性。** 顶层 `let`/`const` 进入全局词法环境，无法删除，第二次求值再声明同名变量就是 SyntaxError，不可行。

### D2 jsLib：独立的 realm，经 Proxy 挂到变量层的原型上

jsLib 第一次用到时，在同一个运行时里新建一个 JSContext（独立的 realm），把 jsLib 当作全局脚本执行一次，然后对它的全局对象 `preventExtensions`。jsLib 的顶层 `var` 和函数声明自然落在这个全局对象上，jsLib 函数改写自己的顶层变量也是改它，所有引用它的求值都能看到。

主 JSContext 里给每个 jsLib 建一个 Proxy 作为变量层的原型：
- `has`、`get` 只对 jsLib 自己新增的全局名生效（执行前后对比全局对象的属性名得到），读的是 jsLib 全局对象上的当前值；内建对象名不经过它，仍用主 realm 的；
- `set` 把值定义到接收者（本次的变量层）上，所以规则代码给 jsLib 的名字赋值只遮蔽、不修改；
- 从变量层沿原型链找到的函数以 `f()` 调用时，`with` 的基对象是变量层，`this` 就是变量层。

jsLib 函数体里用的内建对象来自 jsLib 自己的 realm，这和 MD3 一样：MD3 的共享作用域也有自己那份标准对象。jsLib 执行时没有注入变量，函数体里直接写 `java` 读不到宿主对象，书源要通过 `this.java` 取，也和 MD3 一致。

缓存：每个 worker 按 jsLib 全文的 MD5 缓存 realm，最多 16 个，按最近使用淘汰，与 MD3 的 `SharedJsScope` 相同。jsLib 执行出错时不缓存，错误带回本次求值；该书源之后每次求值都会重试并再次失败，也与 MD3 相同。

**偏离**：MD3 里同一个 jsLib 的状态在所有线程间共享，这里每个 worker 各一份。语料里 4 个有 jsLib 的 B、C 类书源都只定义函数，没有依赖跨任务共享的可变状态。

**备选**：在主 realm 里用 `with (scope) { … }` 执行 jsLib。直接 eval 的 `var` 和函数声明落在包装函数里，不会落到 `scope` 上，要先取出顶层声明名再预定义，依赖解析器内部结构；独立 realm 让引擎自己完成声明提升。

### D3 宿主 API：一张注册表，按「当前帧」分发

宿主函数只在引擎创建时注册一次，形如 `__host.call(api, args)`；预置 JS 根据上下文种类生成三种 `java` 对象和 `cookie`、`cache`、`source`、`book`、`chapter` 对象，它们的方法都转到 `__host.call`。

Dart 侧维护一个**求值帧栈**：每次进入 JS 时压入一帧，记录上下文种类（规则、URL、书源）、对应的 Dart 对象（`AnalyzeRule`、URL 构造器、书源）、当前书籍和章节、所在字段；退出时弹出。`__host.call` 取栈顶帧，按 API 名查表执行。嵌套求值（`java.getString('@js:…')`）自然压入新帧，返回后恢复。帧栈深度超过 10 时抛出不可捕获的错误（D9）。

这样「`java` 在三种上下文里是三个对象」只体现在两处：预置 JS 里三种 `java` 对象各自暴露哪些方法，Dart 注册表里同名 API 按帧的种类选实现（例如 `put`、`get`）。

**备选**：每次求值把 Dart 回调按需重新注册到 `java` 上。注册是按路径写全局对象，嵌套求值会把外层的覆盖掉，而且每次求值都要多次 FFI 调用。

### D4 跨边界的对象：句柄 + 预置 JS 包装

C 侧只传 JSON，不新增 JSValue 级别的接口。需要在 JS 里带方法的 Dart 对象（HTML 元素、元素列表、响应对象、对称加密器）用**句柄**表示：

- Dart 侧每个任务有一张句柄表，对象登记后得到编号；交给 JS 的 JSON 里写成带标记的对象 `{"\u0000h": 编号, "t": 种类}`。
- 预置 JS 在注入变量和接收宿主返回值时，把带标记的对象换成对应的包装类实例（`JsElement`、`JsElements`、`JsResponse`、`JsCipher`），方法调用转成 `__host.call('el.text', [编号])` 等。
- 包装类定义 `toJSON()` 返回同样的标记对象，所以 JS 把它们作为返回值交回 Dart 时，Dart 能还原成原来的元素。
- 句柄表在任务结束时清空。jsLib 状态里如果留着上一个任务的句柄，再用时以「对象已失效」错误结束。

宿主交给 JS 的列表在预置 JS 里补上不可枚举的 `toArray`、`size`、`get`、`isEmpty`（D7）。

`book`、`chapter`、`source` 不用句柄：它们是数据对象，注入时把字段快照成普通属性；`book` 的属性额外定义 setter，赋值时调用 `__host.call('book.set', …)` 写回 Dart 侧的书籍；`chapter`、`source` 只有 getter，非严格模式下赋值被静默忽略，正好是 MD3 的效果。`getVariable` 等方法走 `__host.call`。

**备选**：在 C 侧实现 Dart 对象的 JS 代理（JSClass + finalizer）。性能更好，但要在 C 胶水里管理对象生命周期和跨 isolate 的回调，复杂度高；语料里元素方法的调用量不大，句柄足够。

### D5 进入 JS 的位置都改成调用同一个运行时

新增 `js/source_js.dart`，对规则引擎只暴露几个入口：

- `evalRule(code, frame)`：规则 JS 段和规则里的 `{{JS}}`，`frame` 带 `result`、内容、书籍、章节等；
- `evalUrl(code, frame)`：URL 的 `@js:`、`{{}}`、`js`、`bodyJs` 选项，`loginCheckJs`；
- `evalSource(code, source)`：书源 `header`；
- `evalFormat(code, layer, chapter, index)`：`formatJs`，复用同一个变量层。

现在抛 `NeedsJsException` 的地方逐一换成这些调用。`NeedsJsException` 保留给 `@webjs:` 以外仍不支持的 JS 能力（如 JSON 形式的 jsLib），不支持的宿主 API 用新的 `UnsupportedHostApiException`，两者都带书源名和字段。

URL 模板里的 `{{key}}`、`{{page}}`、`{{baseUrl}}` 也统一按 JS 求值（读注入变量），去掉现在的文本替换特判，语义上与 MD3 一致，也少一条分支。

### D6 值转换：JSON 边界上整数和小数天然区分

JS 返回值经 JSON 交回 Dart：`JSON.stringify(2)` 是 `2`，Dart 解析为 `int`；`2.5` 解析为 `double`。转字符串时 `int` 直接输出，`double` 按 JS 的数字格式输出（`1e21` 这种超出整数范围的也按 JS 格式）。这样 `@js:1+1` 得到 `2`。

**偏离**：MD3 里字面量和算术结果是 Double，`@js:1+1` 作为规则得到 `2.0`；`JSON.parse` 和 `.length` 得到的是 Integer，输出 `2`。Rhino 的这种区别取决于值的来源，quickjs 里没有对应信息，无法复现。书源作者为了在 MD3 里得到整数通常会写 `{{}}`、`parseInt` 后拼字符串或 `String(n)`，这些写法在两边结果相同；只有直接把算术结果作为规则结果的写法会出现 `2` 与 `2.0` 的差别，这里取 `2`。

其余转换照规格。JS 返回的普通对象在规则引擎里作为「JS 对象内容」，单独标记，按 MD3 的 NativeObject 路径处理（只用第一个 SourceRule，按键取值），不和 JSONPath 取到的 JSON 对象混用。

### D7 Java 互操作只做语料里用到的部分

- 元素和元素列表的包装方法、响应对象的方法：按 `research/corpus-js-usage.md` 第 3 节列出的方法实现，结果复用规则引擎里的 jsoup 语义（`html/jsoup_text.dart`、`html/css_selector.dart`）。
- 宿主列表的 `toArray`、`size`、`get`、`isEmpty`：语料里 `.toArray()` 有 40 处，其余各 1 处。
- 不给 `String.prototype` 加 Java 方法。B、C 类里一个都没有用到；加上反而会改变 JS 原生方法的语义（`replaceAll`、`split`）。
- 字节数组用 -128 到 127 的数字数组表示，与 Java `byte[]` 在 JS 里的样子一致（有 `length`、能下标访问）。

### D8 书源级状态放在主 isolate

`cache.*`、书源变量、登录头、登录信息和 Cookie 一样只有一份，放在主 isolate 的 `RuleHost` 上，由新的 `SourceStore` 持有（内存里的键值表，带过期时间）。worker 通过新的宿主请求 `store` 读写，一次一个操作。

- 登录头需要叠加到请求头里，而且顺序在书源 `header` 之后、URL 选项 `headers` 之前，所以在 worker 构造请求时合并：每个任务第一次构造该书源的请求时取一次登录头，任务里 `putLoginHeader` 时同步更新本地副本。
- `java.log`、`toast` 和请求头 JS 的错误通过宿主请求 `log` 交给主 isolate，`RuleHost` 把它们转给调用方注册的日志接收函数，带书源地址和字段。
- `SourceStore` 只定义接口和内存实现，以后的存储层实现同一接口来落盘。

`RuleEnvironment` 增加 `store`、`log` 两个同步方法；测试用的环境直接挂一个内存 `SourceStore`。

**备选**：缓存放在 worker 里。各 worker 各一份，书源在一个任务里 `cache.put`、另一个任务里 `cache.get`（可能在别的 worker 上）就读不到，结果取决于调度。

### D9 取消、超时和嵌套上限

求值都传入任务的中止标志（现有机制），JS 和阻塞在 `callHost` 里的宿主函数都会被中止，`try/catch` 拦不住。

嵌套超过 10 层不能借用任务的中止标志，那会把整个任务变成「已取消」。C 胶水的宿主回调增加一种返回状态「不可捕获的错误」：Dart 侧检测到第 11 层时这样返回，C 侧用 quickjs 的不可捕获异常抛出（与中止用的是同一种机制），一路穿过各层 JS 的 `try/catch`，在最外层求值处还原成「嵌套求值超过 10 层」错误。

### D10 C 胶水的新增接口

- `qjs_layer_new` / `qjs_layer_free`：创建和释放变量层（JS 侧 Map 里的一个对象，Dart 只拿编号），层上的变量沿用现有的 JSON 方式设置；
- `qjs_eval_scoped(engine, layer_id, lib_id, code, abort_flag, …)`：调用预置的 `__run`（D1），`lib_id` 为 0 时不挂 jsLib；
- 宿主回调的错误标志增加「不可捕获」一种取值（D9）；
- `qjs_lib_new(engine, code, …)` / `qjs_lib_free`：在同一个 JSRuntime 里新建 JSContext 执行 jsLib，返回编号，并把它的全局对象交给主 JSContext 里构造 Proxy（D2）。中断处理按运行时设置，jsLib realm 里的代码同样受中止标志约束。

### D11 加解密用 pointycastle

AES、DESede（单 DES 用三段相同密钥的 DESede 实现）、ECB、CBC、PKCS7 填充、MD5、SHA 系列、HMAC 都用 `pointycastle` 4.0.0（MIT，纯 Dart，SDK 要求 `^3.2.0`，2025-02 发布）。Base64 的两套语义（Hutool 宽松、Android 严格及其 flags）自己实现，`dart:convert` 的 Base64 两者都不是。`timeFormatUTC` 的 `SimpleDateFormat` 格式自己实现常用字母。

**备选**：`package:crypto` 只有摘要和 HMAC，没有分组密码；`cryptography` 依赖平台插件，纯 Dart 实现不含 DES。

### D12 测试与验证

- **期望值来源**：加解密、Base64（Hutool 5.8.22 的宽松解码，Android `Base64` 的 flags 语义，取 AOSP 的 `android.util.Base64` 源码，Apache-2.0）、`URLEncoder`、`SimpleDateFormat` 的期望值由 `tool/jsoup_oracle` 下新增的 Java 程序生成，和上一个 change 的 oracle 放在一起。`toNumChapter` 等 MD3 自己的函数按 research 里的语义手写用例，不拷贝 MD3 源码（MD3 是 GPL-3.0）。
- **运行时语义**：隔离、jsLib、值转换、帧栈、句柄的单元测试直接用引擎，不起 worker。
- **链路**：现有的回放环境加上 store 和 log 后，录制若干 B、C 类真实书源作为固定样例；联网冒烟沿用 `tool/smoke.dart`，按 `--only b.json`、`--only c.json` 跑。
- **移动端**：spike 增加一项 C 类书源的四条链路，在 macOS 和 Android、iOS 模拟器（debug 构建）上运行。真机（Android profile 构建）推迟到所有功能开发完成后统一测试，不在本 change 内。

### D13 与 MD3 的偏离汇总

| MD3 的行为 | 本引擎 | 原因 |
|---|---|---|
| `@js:1+1` 作为规则结果是 `2.0` | `2` | D6，quickjs 没有 Integer/Double 之分 |
| JS 数组作为字符串结果是 `NativeArray@哈希` | 逗号连接 | MD3 的结果没有意义，没有书源依赖 |
| 宿主返回的字符串是 Java 字符串对象（`typeof` 为 object，`===` 为假，有 Java 方法） | JS 原生字符串 | D7，B、C 类没有书源用到 Java 方法 |
| jsLib 状态在所有线程间共享 | 每个 worker 一份 | D2 |
| 同一个 AnalyzeRule 求值 16 次后复用内建对象 | 内建对象始终共用一份（同一个 JSContext） | D1，没有书源修改内建对象 |
| 缓存、变量、登录信息落盘 | 只在进程内存 | 存储层未做 |
| `java.log` 只在调试会话里输出 | 总是交给日志接收方，由调用方决定是否显示 | D8 |
| Rhino 不支持 `class`、`async`、`?.` 等 | quickjs 支持 | 超集，不影响已有书源 |
| `timeFormatUTC` 的月份名、星期、上午下午按设备 Locale | 固定简体中文 | worker 里拿不到设备 Locale，取中文设备的默认值；语料里只用到数字格式 |
| 登录信息用 androidId 加密后保存 | 不加密，只在内存 | 存储层未做 |

## Risks / Trade-offs

- [`with` + 直接 eval 让 quickjs 走慢路径] → 书源 JS 都很短（B 类中位数 138 字符），先实测一个上千章节、每章都有 JS 的目录的耗时；如果不可接受，再考虑对不含声明的纯表达式（`{{page*2}}`、`result.trim()`）走普通求值加参数传值的快路径。
- [句柄方法每次调用都要一次 FFI 往返和 JSON 编解码] → 语料里元素方法的调用集中在少数书源；大列表上的 `toArray().map(...)` 是主要开销，包装类的 `toArray` 一次取回所有元素的句柄，`text()` 等仍逐个调用。实测超过 100ms 时再给常用方法加批量接口。
- [书源的混淆代码、内嵌 CryptoJS 在 quickjs 下行为不同] → 冒烟时单独统计 JS 错误类的失败，逐个看是不是运行时问题。
- [登录头在任务内缓存，另一个 worker 同时写入后本任务看不到] → 与 MD3 在多线程下的可见性相当；登录流程这个 change 不做，实际写入登录头的只有 `loginCheckJs` 和规则 JS 自己。
- [pointycastle 与 JDK 在边界情况（错误密钥长度、错误填充）上的异常时机不同] → 规格只要求以 JS 错误结束，oracle 里覆盖这些情况，异常消息不要求一致。
- [跨 realm 的值在 `instanceof` 上的差异] → jsLib 函数返回的数组在主 realm 里 `instanceof Array` 为假（`Array.isArray` 仍为真）；MD3 的共享作用域同样有自己的内建对象，行为一致，不处理。

## Migration Plan

`rule_engine` 的调用方只有 spike 和冒烟工具：`NeedsJsException` 的含义变窄，新增 `JsEvalException`、`UnsupportedHostApiException`；`RuleEnvironment` 多了 `store`、`log`，`RuleHost` 构造时可以传日志接收函数和 `SourceStore`。改动随本 change 一起更新调用方。

实现时补充的两处：
- 目录任务 `chapterListTask` 改为连同书籍一起返回（`TocResult`）：目录链路会更新书籍（章节数、当前章节名，以及 JS 和 `@put` 写入的变量），任务在 worker 里改的是副本，不交回就丢了（冒烟时有书源在正文 JS 里读 `book.totalChapterNum`）。
- 规则引擎内部各处由传 `RuleEnvironment` 改为传任务上下文 `SourceTask`（环境、书源、句柄表、登录头副本、当前字段），JS 需要书源和任务级状态。
