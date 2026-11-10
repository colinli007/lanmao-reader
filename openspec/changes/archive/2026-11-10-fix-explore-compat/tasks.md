## 1. 引擎

- [x] 1.1 `prelude.dart`：`javaPackage` 建包时把 `known` 里不是包代理的值登记到类名注册表；`JavaImporter` 实例加 `importClass`，查找时先找导入的类再找导入的包（D1）。验证：`java_importer_cipher_test.dart` 加测试，覆盖 source-js「importClass 导入已实现的类」「importClass 导入未实现的类」，以及参数是 `java.util` 或普通对象时抛 JS 错误。
- [x] 1.2 `prelude.dart`：包代理的 `apply`、`construct` 按包根区分，MD3 包根下的照旧报「不支持的宿主 API」，其它抛 TypeError（D2）。验证：JS 测试覆盖 source-js「MD3 里没有的类可以捕获」，原有「使用 Packages」场景（`Packages.java.lang.System.currentTimeMillis`）仍以「不支持的宿主 API」结束且 try/catch 拦不住。
- [x] 1.3 `prelude.dart`、`host_api.dart`：`androidId` 从 `unsupported` 移到 `common`，实现按 D3 生成并保存（键 `app.androidId`）。验证：JS 测试覆盖 source-js-api「格式」「不同书源取到同一个值」；同一个存储换一个新的 `SourceTask` 再取仍相同。
- [x] 1.4 用大灰狼聚合书源（scratchpad 里下载的 7632.json）联网复测：发现分类逐个取第一页，再跑 `tool/smoke.dart` 搜索链路。验证：分类能取出来，可点分类除两个登录按钮外都有书；搜索不再报 `java.log`，结果记在这一项下面。

  结果（2026-11-10，用正式代码，书源 🍅大灰狼聚合5.9.30）：
  - 发现：分类能取出来，383 个、可点 355 个。逐个顺序取第一页，前 29 个里两个登录按钮报 `java.startBrowser`（要开浏览器，预期内），其余 27 个都有书（排行榜每页 25 到 40 本，分类每页 4 到 10 本）。顺序跑完全部要约一小时，没有跑完；修复前用等价的临时补丁并发跑过全部 355 个，353 个有书。
  - 搜索：不再报 `java.log`。第一次搜「斗罗大陆」无结果，直接请求服务器的聚合搜索，第一次也要 5 秒左右才返回缓存结果，是服务器端；第二次搜索通过。
  - 新发现（不在本 change 范围）：详情失败，书籍地址是 `data:;base64,…,{"type":"qingtian"}`，引擎不支持 `data:` 地址（报「No host specified in URI」）。MD3 的 AnalyzeUrl 对 `data:` 地址直接解码 base64，不发请求。

## 2. App

- [x] 2.1 `explore_books_page.dart`：第一页为空的提示改为「没有取到书，可能是网站拦截了请求，或者书源规则已经失效」（D4）。验证：`explore_page_test.dart` 的「第一页没有书」改为断言新文案，覆盖 explore「第一页没有书」。

## 3. 验证和文档

- [x] 3.1 引擎 `dart test`、`dart analyze`，app `flutter test`、`flutter analyze`。验证：全部通过，没有新的警告。
- [x] 3.2 `docs/发布说明/v0.1.0.md`「已知的限制」：Java 对象那条按现状改（常用 Java 类和 JavaImporter 已支持，个别没覆盖到的书源会被校验标成失效）；拦截那条写明搜索和发现都取不到。验证：通读一遍，没有书源名、站点名或订阅地址。
- [x] 3.3 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-10）：explore「分类书籍页」、source-js「Rhino 专有写法」、source-js-api「不支持的宿主 API」按 delta 替换，source-js-api 新增「设备编号」；`openspec validate --specs --strict` 21 项通过。
