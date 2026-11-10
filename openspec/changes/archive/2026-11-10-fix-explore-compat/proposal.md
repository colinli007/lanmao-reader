## Why

用户发布前反馈「发现页的排行榜点进去是空的」。2026-11-10 拿用户给的几份书源逐个查过：

- **大多数是网站拦截**：起点中文（腾讯云 WAF 验证页）、69书吧、铅笔小说、猫扑中文文学（Cloudflare 403）、快书网（JS 跳转验证）。这些要内置 WebView 才能过，不在本 change 里。书旗小说（APP 接口）的 47 个分类、速读谷、番茄小说2 都正常。
- **大灰狼聚合是引擎的兼容 bug**：搜索和发现全部失败，报「不支持的宿主 API：java.log」。临时补上下面三处后，355 个可点分类里 353 个取到书，剩下 2 个是要开浏览器的登录按钮。三处按执行顺序：
  1. jsLib 顶层执行 `new JavaImporter()` 后调 `javaImport.importClass(Packages.java.net.URL)` 等，我们的 JavaImporter 没有 `importClass`，抛出 TypeError。书源的 catch 里调 `java.log`，jsLib 词法作用域里的 `java` 是 Java 包，结果以「不支持的宿主 API：java.log」结束。jsLib 每次求值都要加载，所以整个书源失效。
  2. 分类脚本用 `try { new Packages.io.legato.kazusa.utils.TimeoutCancellationException('') } catch (e) {}` 检测改版阅读。这个类 MD3 里也没有，Rhino 抛可以捕获的 TypeError；我们按 add-rhino-compat D3 一律做成拦不住的「不支持的宿主 API」。D3 的理由是「Rhino 里这些写法能正常执行」，只对 MD3 里存在的类成立。
  3. 接着调 `java.androidId()`，它在「不支持的宿主 API」名单里。MD3 返回设备的 ANDROID_ID，不需要界面或设备能力，本质是「这台设备上稳定的编号」。

另外，分类书籍页第一页为空时只显示「没有书」，用户分不清是这个分类本来没书，还是网站拦截了请求。

## What Changes

- **`JavaImporter` 的 `importClass(类…)`**：按短类名登记导入的类，在 `with` 里可以访问。我们没实现的类照样登记，调用或 `new` 时才以「不支持的宿主 API」结束，和「引用的时候不报错，用的时候才报」的现有规则一致。
- **MD3 里没有的 Java 类按 Rhino 抛 JS 错误**：调用或 `new` 一个 Java 类路径时，包根在 MD3 运行时带的包里（`java`、`javax`、`android`、`androidx`、`kotlin`、`okhttp3`、`org.jsoup`、`io.legado` 等）的，照旧以拦不住的「不支持的宿主 API：类名」结束；不在的，以可以捕获的 TypeError 结束，和 Rhino 一样。
- **`java.androidId()`**：返回 16 位小写十六进制的编号，第一次调用时随机生成并保存，之后一直返回同一个值（随 app 数据保存，卸载后重新生成）。从「不支持的宿主 API」名单里移除。
- **分类书籍页第一页为空的提示**：「没有书」改为「没有取到书，可能是网站拦截了请求，或者书源规则已经失效」。翻页到底的「没有更多了」不变。
- **发布说明**：「已知的限制」里 Java 对象那一条已经过时（JavaImporter、AES、RSA 等已经补上），改成按现状写；拦截那一条补上发现页。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `source-js`：「Rhino 专有写法」加 `importClass`，并区分 MD3 里存在和不存在的类。
- `source-js-api`：「不支持的宿主 API」去掉 `androidId`；新增「设备编号」要求。
- `explore`：「分类书籍页」第 1 页没有书时的提示。

## Impact

- `packages/rule_engine/lib/src/js/prelude.dart`：`JavaImporter.importClass`、Java 包代理的调用和 `new`、`androidId` 移出不支持名单。
- `packages/rule_engine/lib/src/js/host_api.dart`：`androidId` 的实现（经书源级存储读写）。
- `app/lib/online/explore_books_page.dart`：空列表的提示文案。
- 测试：引擎 JS 测试（importClass、MD3 里没有的类可以捕获、MD3 里有但未实现的类仍拦不住、androidId 稳定）；app 分类书籍页的 widget 测试。用大灰狼聚合书源联网复测发现和搜索链路。
- `docs/发布说明/v0.1.0.md`：「已知的限制」两条。
