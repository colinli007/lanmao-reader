## 1. 引擎

- [x] 1.1 `analyze_url.dart`：加 `dataUriBytes`（D2），`fetch()` 在 `type` 不为空时先试 `data:`（D1）。验证：测试覆盖 source-request「type 选项的 data 地址」（详情链路不发请求，正文是十六进制）和「不带 type 的 data 地址」（照常发请求）。
- [x] 1.2 `chains.dart`：正文图片的 `data:` 改用 `dataUriBytes`，去掉 `_dataUriBytes`。验证：`content_image_test.dart` 通过，并加测试：数据里带空格时按 Android 规则跳过（MD3 的正则 `.` 不跨换行，换行会截断数据，和 MD3 一致，不测换行）；不是 base64 的 data 地址以错误结束。

## 2. 验证

- [x] 2.1 引擎 `dart test`、`dart analyze`，app `flutter test`。验证：全部通过。

  结果（2026-11-10）：引擎 1036 个通过（1 个跳过），app 420 个通过，`dart analyze` 无问题。
- [x] 2.2 用大灰狼聚合书源联网跑 `tool/smoke.dart` 的搜索 → 详情 → 目录 → 正文。验证：详情不再报 `No host specified`；结果和后面卡住的地方记在这一项下面。

  结果（2026-11-10，🍅大灰狼聚合5.9.30，关键词「斗罗大陆」）：四条链路全部通过，共 6 个请求。搜索 75 本；详情《斗罗大陆V：重生唐三》唐家三少，书籍地址是 `data:…,{"type":"qingtian"}`；目录地址也是 `data:…,{"type":"qingtian2"}`，1184 章，「引子」到「第1183章 斗罗，大团圆」；正文「引子」15764 字，里面有 `data:image/svg+xml;base64` 的图片（走正文图片的 `data:` 解码）。没有再卡住的地方。
- [x] 2.3 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-10）：source-request「URL 选项」、book-chains「正文图片」按 delta 替换；`openspec validate --specs --strict` 21 项通过。
