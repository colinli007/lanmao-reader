## Why

2026-11-03 用户导入 yckceo 的书源合集 1329（320 个书源）后搜索，失败 140 个。逐个排查后发现，有两类失败是我们的兼容问题，不是网站的问题：

- 书源 JS 里写 `source.key`（25 个书源用到），我们拿到的是 undefined，典型写法 `cookie.removeCookie(source.key)` 直接报「第 1 个参数不能为 null」。Legado 用 Rhino 执行书源 JS，Rhino 把 Java 的无参 getter 当成同名属性：`BaseSource.getKey()` 可以写成 `source.key`（值是书源地址），`getTag()` 可以写成 `source.tag`（值是书源名）。我们只提供了方法写法。
- URL 的 JS 和 `loginCheckJs` 里写 `java.url`、`java.ruleUrl`（两份真实合集里共 12 处），我们拿到的是 undefined。这两个是 MD3 `AnalyzeUrl` 的公开属性：当前请求的地址、替换过 `{{}}` 的地址规则。

## What Changes

- 书源对象 `source` 增加只读属性 `key`（书源地址）和 `tag`（书源名），和 `getKey()`、`getTag()` 的值相同。
- URL 上下文的 `java`（URL 的 `@js:`、`<js>`、`{{}}`，选项 `js`、`bodyJs`，`loginCheckJs`）增加只读属性 `url`（当前请求的地址）和 `ruleUrl`（替换过 `{{}}`、还带着选项的地址规则），每次读取时取当前值。
- **不做**：`AnalyzeUrl` 其它属性（`type`、`urlNoQuery`）和 `getUrl()` 等方法写法，两份合集里都没有用到；给这些属性赋值（Rhino 里能写回）也不做，同样没有用到，赋值按只读忽略。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `source-js`：「书籍、章节和书源对象」写明 `source.key`、`source.tag`。
- `source-js-api`：URL 上下文的 `java` 写明 `url`、`ruleUrl` 两个属性。

## Impact

- **rule_engine**：`source_js.dart` 的 `sourceFields` 加上 `key`、`tag`；`prelude.dart` 给 URL 上下文的 `java` 定义 `url`、`ruleUrl` 两个读取器；`host_api.dart` 新增对应的两个宿主调用。
- **测试**：`source_js_api_test.dart`、`analyze_url_test.dart`。
- app 不用改。
