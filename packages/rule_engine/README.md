# rule_engine

Legado 书源规则引擎：载入书源，解析规则，执行搜索、详情、目录、正文四条链路。书源里的 JS 在 quickjs-ng 上执行，注入不依赖界面和 WebView 的常用宿主 API；需要 WebView 的地方以 `NeedsWebViewException`、调用不支持的宿主 API 以 `UnsupportedHostApiException` 明确报错，不会静默跳过。

行为以 legado-with-MD3（commit `d1b488b`）为准，包括它的怪异行为。书源作者是对着 Legado 调的规则，对齐才是兼容。规格见 `openspec/specs/` 下的 `book-source`、`rule-syntax`、`source-request`、`book-chains`、`source-js`、`source-js-api`，设计见 `openspec/changes/archive/` 里的 add-rule-engine 和 add-js-runtime。

## 用法

```dart
// 主 isolate：网络、Cookie、限速、书源级状态（缓存、书源变量、登录头）都在 RuleHost 里，所有 worker 共用；
// 书源 JS 的调试日志（java.log、降级的 toast、请求头 JS 的错误）写入时就交给 onLog
final host = RuleHost(onLog: (log) => print(log));
final pool = WorkerPool(host.handle, size: 4);

final sources = loadBookSources(json).sources;          // 跳过的条目在 .skipped 里
final books = await pool.run(searchTask(source, '三体'), cancelToken: token);
final book = await pool.run(bookInfoTask(source, books.first.toBook()));
final toc = await pool.run(chapterListTask(source, book));  // 章节和更新过的书籍
final chapters = toc.chapters;
final content = await pool.run(contentTask(source, toc.book, chapters[0],
    nextChapterUrl: chapterAbsoluteUrl(chapters[1])));   // 多页正文遇到下一章时停止
```

链路之间传递的 `SearchBook`、`Book`、`BookChapter` 都是普通对象，带着 `@put` / `java.put` 的变量和保存的页面（搜索直达详情页、目录就在详情页时，下一条链路不再请求）。目录任务在 worker 里改的是书籍的副本（章节数、当前章节名、JS 写入的变量），所以连同书籍一起交回。

错误都继承 `RuleEngineException`，带书源名和字段（如 `ruleToc.chapterName`）：`RuleException`（规则错误）、`JsEvalException`（JS 错误）、`UnsupportedHostApiException`（不支持的宿主 API，`api` 是名字）、`NeedsWebViewException`、`NeedsJsException`（不支持的 JS 用法，如 JSON 形式的 jsLib）。可选字段（分类、字数、简介等）的规则错误和 JS 错误照 MD3 吞掉；缺少的能力不吞。

## 结构

- **核心层**（同步，不感知 isolate）：`chain/`（四条链路）、`rule/`（规则拆分和取值）、`request/`（请求构造、响应解码）、`html/`（jsoup 语义、CSS 选择器、XPath）、`json/`（JSONPath）。网络和取消通过 `RuleEnvironment` 注入，测试用回放环境，不起 isolate、不联网。
- **worker 端**：`WorkerRuleEnvironment` 通过阻塞桥把请求交给主 isolate；`searchTask` 等任务工厂交给 `WorkerPool.run`。
- **主 isolate 端**：`RuleHost.handle` 处理 `http`、`httpBatch` 宿主请求，用 `dart:io` 的 `HttpClient`。

书源提供的正则在 quickjs-ng 的 libregexp 里执行（`quickjs_ng_ffi` 的 `JsRegExp`），任务取消或超时后，灾难性回溯的正则也能停下，worker 不会被放弃。

## 书源 JS

`js/` 目录：

- `source_js.dart`：运行时。每个 isolate 一个引擎；进入 JS 的地方都走这里：`evalRule`（规则里的 `@js:`、`<js>`、`{{}}`）、`evalUrl`（URL 里的 JS、`js` / `bodyJs` 选项、`loginCheckJs`）、`evalSource`（书源 `header`）、`formatChapterTitles`（目录的 `formatJs`）。
  - 每次求值用新的变量层（`quickjs_ng_ffi` 的隔离求值），顶层 `var`、函数声明、未声明的赋值都不泄漏；`formatJs` 的所有章节共用一个变量层。
  - jsLib 在独立的 realm 里执行一次，按全文的 MD5 缓存 16 个（每个 worker 一份）。
  - 宿主 API 只注册一个 `__host.call`，按求值帧分发：规则、URL、书源三种上下文的 `java` 是三个不同的对象。嵌套求值最多 10 层。
  - 不支持的宿主 API、需要 WebView 等错误在 JS 里不可捕获，最外层还原成原来的错误类型；取消和截止时间同样拦不住。
- `prelude.dart`：预置 JS，把宿主调用包装成 `java`、`cookie`、`cache`、`source`、`book`、`chapter` 和元素、响应、加密器的包装类。
- `js_values.dart`：跨边界的值。都是 JSON；Dart 侧的对象用带标记的 JSON 表示，元素、响应、加密器通过任务级的句柄表传递（任务结束失效）。JS 交回的对象、数组、非整数数字分别是 `JsObject`、`JsArray`、`JsNumber`，转字符串按 JS 的 `String()`。
- `host_api.dart`：宿主 API 的实现，语义照 MD3（见 add-js-runtime 的 `research/md3-host-api.md`）。
- `codec.dart`、`crypto.dart`、`time_text.dart`：两套 Base64（Hutool 宽松、Android 严格）、表单编码、字符集、摘要、HMAC、AES/DES/DESede（`pointycastle`）、`SimpleDateFormat`、`toNumChapter`。期望值由 `tool/jsoup_oracle/CodecOracle.java` 用 JDK、Hutool 和 AOSP 的 `android.util.Base64` 生成。

书源级状态（`cache.*`、书源变量、登录头、登录信息、Cookie）在主 isolate 的 `RuleHost` 上只有一份，worker 通过宿主请求 `store` 读写。引擎只带内存实现：要落盘时，调用方给 `RuleHost` 传入自己的 `SourceStore`（app 的实现是启动时全部载入内存、写入后台落盘），以及带初始值和变更回调的 `CookieStore(persistent: 上次保存的持久 Cookie, onPersistentChanged: …)`：持久 Cookie 每次被改写后用这个域名的新值回调一次（删除时为 null），会话 Cookie 不落盘。登录头在每个任务第一次构造请求时取一次。

开销（macOS，Apple M4，`tool/bench_toc_js.dart`）：2000 章的目录，章节名和地址都带 JS 时目录链路约 210 ms，再加 `formatJs` 约 260 ms；纯规则约 40 ms。

## 与 MD3 的偏离

书源 JS（设计 D13）：

| MD3 的行为 | 本引擎 | 原因 |
|---|---|---|
| `@js:1+1` 作为规则结果是 `2.0` | `2` | Rhino 区分 Integer 和 Double 取决于值的来源，quickjs 没有对应信息 |
| JS 数组作为字符串结果是 `NativeArray@哈希` | 逗号连接 | MD3 的结果没有意义 |
| 宿主返回的字符串是 Java 字符串对象（`typeof` 为 object，`===` 为假，有 Java 方法） | JS 原生字符串 | B、C 类书源没有用到 Java 字符串方法 |
| jsLib 状态在所有线程间共享 | 每个 worker 一份 | 每个 isolate 一个引擎 |
| 同一个 AnalyzeRule 求值 16 次后复用内建对象 | 内建对象始终共用一份 | 同一个 JSContext，没有书源修改内建对象 |
| 缓存、变量、登录信息落盘；登录信息用 androidId 加密 | 只在进程内存，不加密 | 存储层未做 |
| `java.log` 只在调试会话里输出 | 总是交给日志接收方 | 由调用方决定是否显示 |
| Rhino 不支持 `class`、`async`、`?.` 等 | quickjs 支持 | 超集，不影响已有书源 |
| `timeFormatUTC` 的月份名、星期、上午下午按设备 Locale | 固定简体中文 | 中文设备的默认值 |
| `Packages`、`JavaImporter`、`org.jsoup` 等 Java 互操作 | 以 JS 错误结束 | 不模拟 Java 互操作 |

规则引擎的其它部分只在 MD3 自己会出错的地方偏离：

| MD3 的行为 | 本引擎 |
|---|---|
| 详情 `init` 用正则或 JSONPath 取不到时 `setContent(null)` 抛 AssertionError | 以「详情 init 取不到」错误结束 |
| `@css:` 取字符串的规则里没有 `@` 时越界崩溃 | 以规则错误结束 |
| `http-equiv` 的 content 里没有 `charset=` 时，把整段当编码名，抛错 | 按没有声明处理 |
| 无法判定编码时用 ICU 自动检测 | 合法 UTF-8 就按 UTF-8 解码，否则按 GBK 解码 |
| 区间索引在 len=0 时越界 | 结果为空 |
| 多页并发时 body 为空抛 NPE | 这一页按空内容处理 |
| 页码 `page=0` 越界 | 按第 1 页处理 |

其余已知差异：

- 编码只支持 UTF-8、GBK 一族（GBK、GB2312）、GB18030（按 WHATWG 的 gb18030）和 ISO-8859-1；Big5 等按没有声明处理。
- 书源正则的 `\d`、`\w` 按 Android（ICU）的 Unicode 语义转换，限 BMP；字符类里的 `\D`、`\W` 和 `\b` 仍是 ASCII 语义。
- JsoupXpath 在 `..` 和 `descendant` 轴上的结果顺序取决于对象哈希，本身不确定；这里按文档顺序。
- 没有 MD3 的 Cookie 4096 字节上限；不做 HTTP 缓存、代理、`dnsIp`。

## 测试

```bash
(cd ../quickjs_ng_ffi && ./tool/build_host.sh)
export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
dart test

# 可选：载入 aoaostar 全量书源，核对跳过数
LEGADO_SOURCES_DIR=<aoaostar/legado>/sources dart test test/book_source_test.dart
```

- `test/fixtures/` 下 jsoup、JSONPath、XPath、URL 拼接、编码与加解密、日期格式的期望值由 `tool/jsoup_oracle/` 用 MD3 锁定版本的 Java 库和 JDK 生成，见那里的 README。
- 书源 JS 的规格场景在 `source_js_test.dart`（执行模型）、`source_js_api_test.dart`（宿主 API，网络部分用本地 HTTP 服务和 worker 池）、`chains_js_test.dart`（链路里的 JS）。
- `test/fixtures/recorded/` 是真实书源的录制样例，`recorded_test.dart` 不联网重放。

## 联网冒烟和录制

```bash
dart run tool/smoke.dart --sources 书源.json --key 斗罗大陆 [--only a.json] [--shuffle 1 --limit 200] \
    [--concurrency 16] [--json 结果.json] [--record 目录]
```

对每个书源依次跑搜索、详情、目录、第一章正文，输出各链路的成功数和失败原因分布（JS 错误按错误类型、不支持的宿主 API 按名字归类）。`--only` 是 source-check（`--list --level a --json`）的输出，只测其中列出的书源；`--json` 的结果里带着每个书源 JS 写的日志；`--record` 把每个书源的全部请求和响应存成样例，补上人工核对过的 `expected` 后放进 `test/fixtures/recorded/`。

## 生成的文件

- `lib/src/text/gbk_table.dart`：`tool/gen_gbk.dart` 从 WHATWG 的 `index-gb18030.txt` 和 `index-gb18030-ranges.txt` 生成。
- `lib/src/net/public_suffix_list.dart`：`tool/gen_public_suffix.dart` 从 publicsuffix.org 的列表生成（MPL-2.0）。
