## 1. 引擎

- [x] 1.1 rule_engine：`getContentImage(env, source, book, src)` 和 `imageTask`：`data:` 地址、按书源构造请求取原始字节、非 2xx 报错、`imageDecode`（`SourceJs` 加入口，注入 `book`、`result`、`src`，返回值转字节，null 报错）（D9）。验证：新测试覆盖 book-chains「正文图片」的四个场景，用回放环境不连网。

  结果（2026-11-04）：`chains.dart` 加 `getContentImage`，`SourceJs.evalImageDecode` 注入 `java`、`source`、`book`、`result`、`src`（和 MD3 的 `BaseSource.evalJS` 一样）；宿主 API 的 `_bytes` 改成公共的 `jsBytes`，`imageDecode` 的返回值也用它转。`content_image_test.dart` 6 个用例（多了一个地址选项里的请求头）。
- [x] 1.2 app：`SourceEngine.image`、`PoolSourceEngine` 直接提交；`BookContentSource.loadImage`、`OnlineContentSource` 实现；`FakeEngine` 跟着改。验证：analyze 通过，现有测试通过。

  结果（2026-11-04）：另外加了 `BookContentSource.imageStyle`（书源的 `ruleContent.imageStyle`），阅读页拆段时用；`TestServices` 加 `contentSource` 字段。

## 2. 存储

- [x] 2.1 `database.dart`：新表 `ContentImages`，schemaVersion 4，`from < 4` 建表；读写；所有删除正文的地方一起删图片；`contentCacheStats` 加上图片字节（D7）。验证：`database_test.dart` 覆盖读写、移出书架、启动清理浏览中的书、换书源、清除正文缓存、统计、从 v3 升级。

  结果（2026-11-04）：表类叫 `CachedImages`（`ContentImages` 和阅读页的图片类重名），SQL 表名仍是 `content_images`。删除正文的地方只有三处：`removeBook`（换书源也走它）、`purgeBrowsingBooks`、`clearContents`，都加上了图片。新增 3 个用例，20 个都通过。

## 3. 格式化和图片

- [x] 3.1 `chapter_format.dart`：`<img src>` 换成 U+FFFC，记下地址和选项；量完尺寸后按样式拆段、算偏移（D2、D3）。验证：`chapter_format_test.dart` 覆盖块状拆段、行内保留、偏移、选项里的 `style` 和 `width`、加载失败。

  结果（2026-11-04）：`ContentImage` 不可变，`arrangeImages` 量完尺寸后生成新对象；地址的匹配用 Legado 的 `AppPattern.imgPattern`（选项里有引号）。8 个用例通过。
- [x] 3.2 新增 `content_images.dart`：读缓存或下载（并发 4）、量尺寸、失败不写缓存（D1）；按显示尺寸解码、50MB 的 LRU、解码完成通知（D4）。验证：单元测试覆盖缓存命中不下载、并发上限、失败、LRU 淘汰。

  结果（2026-11-04）：4 个用例。写的时候踩到一个死锁：`whenComplete(() => _loading.remove(src))` 的回调返回了这个 Future 自己，`whenComplete` 等它完成就永远等不到；改成回调不返回值。

## 4. 排版和绘制

- [x] 4.1 `chapter_layout.dart`：块状图的段（一行）、`SINGLE` 换页居中、行内占位（D5、D6）；画块状图和行内图，没解码好时画浅色方框，加载失败画方框和文字；`retainAround` 预解码；`pageText` 里图片写成「[图片]」；`imageAt(page, position)`。验证：`chapter_layout_test.dart` 覆盖 reader「正文图片」的尺寸、分页、独占一页场景和偏移。

  结果（2026-11-04）：`SegmentPainter` 改成密封类，分 `TextSegmentPainter`（原来的，加行内图）和 `ImageSegmentPainter`；旧测试取 `first`、`rest` 的地方加了类型转换，soak 测试跟踪的类名跟着改。新增 5 个用例，原有阅读测试 137 个照常通过。
- [x] 4.2 阅读页：`_formatted` 接上图片（D1）；分页和滚动视图解码完成后重画；长按图片打开 `ImageViewerPage`（D8）。验证：`reader_page_test.dart` 覆盖图片显示、失败重试、长按看大图和点一下关闭、点击图片照常翻页。

  结果（2026-11-04）：图片和窗口一起创建（要用屏幕像素密度），窗口持有它，分页视图自己按长按位置找图、打开大图页；滚动模式只给有图片的段落加长按。新增 4 个用例。

## 5. 验证和文档

- [x] 5.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`，rule_engine `dart test`。验证：全部通过。

  结果（2026-11-04）：app 344 个、rule_engine 907 个通过，两边 analyze 都没有问题。
- [x] 5.2 Android 模拟器上用带插图的书源走一遍：插图、字图片（有的话）、长按大图、翻页、重启后不再请求、清除缓存。验证：截图给用户看。

  结果（2026-11-04，Android 模拟器 API 36，debug 包）：合集 1329 里正文带图的文本书源大多是漫画站或境外轻小说站，模拟器上不好搜（不能输入中文），所以在 Mac 上用 `python3 -m http.server` 搭了一个测试站（模拟器经 `10.0.2.2` 访问），四章分别是插图、字图片、`SINGLE`、取不到的图。结果：
  - 600×400 的插图缩到正文宽；300×1500 的图缩到一页高、水平居中；长按打开黑底大图，点一下回到原来那一页。
  - 20×20 的字图片嵌在文字里，一个字宽，两端对齐照常。
  - `SINGLE`：第 1 页文字，第 2 页只有图片、垂直居中，后面的文字从第 3 页开始。
  - 取不到的图显示「图片加载失败」方框；把图补上、重启后再打开这一章，重新请求并显示出来。
  - 重启后从目录跳回第一章，插图不再请求（测试站的访问日志里 big.png 只有 1 次）。
  - 设置页「正文缓存」6 章 · 29.7 KB（含约 9.6 KB 图片）；清除后变成 0 章，再打开第一章时插图重新请求。
- [x] 5.3 PRD 4.5 节「正文图片」标为已完成；README 同步。验证：通读一遍。
- [x] 5.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。

  结果（2026-11-05）：用户确认后同步到主规格并归档。
