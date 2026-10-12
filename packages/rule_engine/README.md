# rule_engine

Legado 书源规则引擎：载入书源，解析规则，执行搜索、详情、目录、正文四条链路。目前支持不需要 JS 的书源（A 类）；需要 JS 或 WebView 的地方以 `NeedsJsException` / `NeedsWebViewException` 明确报错，不会静默跳过。

行为以 legado-with-MD3（commit `d1b488b`）为准，包括它的怪异行为。书源作者是对着 Legado 调的规则，对齐才是兼容。规格见 `openspec/specs/` 下的 `book-source`、`rule-syntax`、`source-request`、`book-chains`，设计见 `openspec/changes/archive/` 里的 add-rule-engine。

## 用法

```dart
// 主 isolate：网络、Cookie、限速都在 RuleHost 里，所有 worker 共用
final host = RuleHost();
final pool = WorkerPool(host.handle, size: 4);

final sources = loadBookSources(json).sources;          // 跳过的条目在 .skipped 里
final books = await pool.run(searchTask(source, '三体'), cancelToken: token);
final book = await pool.run(bookInfoTask(source, books.first.toBook()));
final chapters = await pool.run(chapterListTask(source, book));
final content = await pool.run(contentTask(source, book, chapters[0],
    nextChapterUrl: chapterAbsoluteUrl(chapters[1])));   // 多页正文遇到下一章时停止
```

链路之间传递的 `SearchBook`、`Book`、`BookChapter` 都是普通对象，带着 `@put` 的变量和保存的页面（搜索直达详情页、目录就在详情页时，下一条链路不再请求）。

## 结构

- **核心层**（同步，不感知 isolate）：`chain/`（四条链路）、`rule/`（规则拆分和取值）、`request/`（请求构造、响应解码）、`html/`（jsoup 语义、CSS 选择器、XPath）、`json/`（JSONPath）。网络和取消通过 `RuleEnvironment` 注入，测试用回放环境，不起 isolate、不联网。
- **worker 端**：`WorkerRuleEnvironment` 通过阻塞桥把请求交给主 isolate；`searchTask` 等任务工厂交给 `WorkerPool.run`。
- **主 isolate 端**：`RuleHost.handle` 处理 `http`、`httpBatch` 宿主请求，用 `dart:io` 的 `HttpClient`。

书源提供的正则在 quickjs-ng 的 libregexp 里执行（`quickjs_ng_ffi` 的 `JsRegExp`），任务取消或超时后，灾难性回溯的正则也能停下，worker 不会被放弃。

## 与 MD3 的偏离

只在 MD3 自己会出错的地方偏离：

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

- 编码只支持 UTF-8、GBK 一族（GB2312、GB18030 的双字节部分）和 ISO-8859-1；Big5 等按没有声明处理。
- 书源正则的 `\d`、`\w` 按 Android（ICU）的 Unicode 语义转换，限 BMP；字符类里的 `\D`、`\W` 和 `\b` 仍是 ASCII 语义。
- JsoupXpath 在 `..` 和 `descendant` 轴上的结果顺序取决于对象哈希，本身不确定；这里按文档顺序。
- Cookie 只存在内存里，没有 MD3 的 4096 字节上限；不做 HTTP 缓存、代理、`dnsIp`。

## 测试

```bash
(cd ../quickjs_ng_ffi && ./tool/build_host.sh)
export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
dart test

# 可选：载入 aoaostar 全量书源，核对跳过数
LEGADO_SOURCES_DIR=<aoaostar/legado>/sources dart test test/book_source_test.dart
```

- `test/fixtures/` 下 jsoup、JSONPath、XPath、URL 拼接的期望值由 `tool/jsoup_oracle/` 用 MD3 锁定版本的 Java 库生成，见那里的 README。
- `test/fixtures/recorded/` 是真实书源的录制样例，`recorded_test.dart` 不联网重放。

## 联网冒烟和录制

```bash
dart run tool/smoke.dart --sources 书源.json --key 斗罗大陆 [--only a.json] [--shuffle 1 --limit 200] \
    [--concurrency 16] [--json 结果.json] [--record 目录]
```

对每个书源依次跑搜索、详情、目录、第一章正文，输出各链路的成功数和失败原因分布。`--only` 是 source-check（`--list --level a --json`）的输出，只测 A 类书源；`--record` 把每个书源的全部请求和响应存成样例，补上人工核对过的 `expected` 后放进 `test/fixtures/recorded/`。

## 生成的文件

- `lib/src/text/gbk_table.dart`：`tool/gen_gbk.dart` 从 WHATWG 的 `index-gb18030.txt` 生成。
- `lib/src/net/public_suffix_list.dart`：`tool/gen_public_suffix.dart` 从 publicsuffix.org 的列表生成（MPL-2.0）。
