## 1. 接口和存储

- [x] 1.1 `library/content_cache.dart`：`cacheContentImage(db, source, book, src)` 从 `ContentImages` 移过来，阅读页改用它（D3）。验证：`content_images_test.dart` 照常通过。

  结果（2026-11-05）：`imageSizeOf` 也一起移过来了，`ContentImages.prepare` 改调 `cacheContentImage`。
- [x] 1.2 `BookContentSource.cacheChapters` 和 `ChapterCaching`；`OnlineContentSource` 实现：`Batch`、经批量限流器的正文任务、等 1 秒重试最多 3 次、书源不存在时每章失败（D1）。验证：单元测试覆盖成功、重试后成功、3 次都失败、停止、书源不存在。

  结果（2026-11-05）：`cacheChapters(book, toc, indices)` 传整本目录，多页正文要用下一章的地址；重试间隔是 `OnlineContentSource` 的参数，测试里是 0。`chapter_caching_test.dart` 4 个用例。
- [x] 1.3 `database.dart`：每本书已缓存的章节数和不是卷的章节总数的数据流（D5）。验证：`database_test.dart` 覆盖计数和变化。

  结果（2026-11-05）：`watchCacheCounts` 用一条 LEFT JOIN 的 SQL（读 chapters、contents 两张表，写入时数据流跟着变）；另加 `cachedChapterUrls` 给范围计数用。

## 2. 控制器

- [x] 2.1 `bookshelf/book_cache.dart`：`bookCacheProvider`：发起（按范围取未缓存的非卷章节）、合并、写正文缓存、补图片、结束、停止、移出书架时停止（D2、D4）。验证：单元测试覆盖 book-cache「下载章节」的场景（用假的链路执行方）。

  结果（2026-11-05）：`book_cache_test.dart` 3 个用例（计数、正文和图片写入及失败数、合并和停止）；书架上移出书架、换书源时停止这本书的任务。

## 3. 界面

- [x] 3.1 书架长按选项单加「缓存」，范围选择（数量、全部已缓存时的提示），开始后提示去哪里看进度（D4）。验证：`bookshelf_page_test.dart` 覆盖「选范围」「已经全部缓存」。

  结果（2026-11-05）：选项单多了一项后，有「失败原因」时在 800×600 的测试窗口里超出了底部弹层默认的最大高度（屏幕高的 9/16），`showActionSheet` 改成 `isScrollControlled` 加滚动，矮窗口里也不会溢出。范围选择是 `cache_page.dart` 里的 `chooseCacheRange`，书架和缓存管理页共用。
- [x] 3.2 `bookshelf/cache_page.dart` 缓存管理页；设置页「正文缓存」一行点了进入（D5）。验证：widget 测试覆盖「看进度和停止」「从缓存管理页发起」、空书架。

  结果（2026-11-05）：`cache_page_test.dart` 2 个用例，设置页测试加「点正文缓存进入缓存管理页」。

## 4. 验证和文档

- [x] 4.1 全量检查：app 带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，`flutter analyze`。验证：全部通过。

  结果（2026-11-05）：app 357 个通过，analyze 没有问题。
- [x] 4.2 Android 模拟器上：缓存一本真实书源的书和测试站的插图书，在缓存管理页看进度、停止、再发起；关掉模拟器网络后读后面的章节。验证：截图给用户看。

  结果（2026-11-05，Android 模拟器 API 36，debug 包）：
  - 测试站的插图书 `chatu`：长按「缓存」显示「共 4 章，已缓存 2 章」和两个「（2 章）」，选「全部章节」后提示去哪里看进度；测试站日志里章节图片（wide.png、zi.png）被下载。
  - 《斗破苍穹》（米读小说书源，1663 章）：选「从当前章往后（1663 章）」，缓存管理页显示「已缓存 20 / 1663 章 · 缓存中 20 / 1663」和「停止」；20 秒里从 35 章到 61 章（约每秒 1.3 章）；点「停止」后停在 68 章，不再增加。
  - 关掉模拟器的 Wi-Fi 和移动数据（ping 10.0.2.2 不通）后，从目录打开 `chatu` 第三章，正文和独占一页的图片照常显示。测完打开了网络。
- [x] 4.3 PRD 4.4 节「缓存全本」标为已完成；README 同步。验证：通读一遍。
- [x] 4.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。
