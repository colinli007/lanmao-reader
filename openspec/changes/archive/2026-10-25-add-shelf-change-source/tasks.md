## 1. 章节对齐（library/relocate.dart）

- [x] 1.1 章节编号和纯章节名的解析（D3）：
  - 取第一处「第 N 章 / 节 / 回」的 N，没有时取开头的数字；全角数字先转成半角
  - 中文数字按进位解析，支持零、〇、两
  - 纯章节名：去掉编号匹配到的那一段，再去掉标点、符号和空白

  验证：`test/library/relocate_test.dart` 新增用例：
  - 「第10章 云涌」「第十章　云涌！」「第一百零五回」「第两千章」「012 标题」「第一卷 第10章 云涌」的编号和纯章节名
  - 「番外」「上架感言」没有编号
- [x] 1.2 `alignChapter(chapters, index:, title:)` 返回 `({int index, bool matched})`，按规格「换书源后定位当前章节」的五步实现，只在不是卷的章节里查找。验证：`relocate_test.dart` 新增用例，一条对应规格的一个场景：
  - 章节名相同，编号写法不同
  - 章节名对不上，编号对得上
  - 同名章节取最近的（距离相同时取序号小的）
  - 同名但编号不同不算
  - 都对不上（序号截到新目录范围内）
  - 卷不参与查找（新目录不会为空：目录为空时目录链路已经以错误结束）

## 2. 存储（storage/database.dart）

- [x] 2.1 `changeSource(oldBookUrl, book, toc)`：在一个事务里依次执行（D4）：
  - 删除旧书的正文、目录、书籍行
  - 用 `insertOrReplace` 写入新书
  - 替换新地址的目录，新地址的正文不动

  验证：`test/storage/database_test.dart` 新增用例：
  - 旧地址的书、目录、正文都没有了
  - 新书在书架上，加入时间、最近阅读时间、进度和传入的一致
  - 新地址原来是浏览中的书、带 2 章正文时，替换后正文还在，`inShelf` 为真
  - source_kv 和 cookies 的行不变
  - 用文件数据库关闭再打开后，`purgeBrowsingBooks` 不会清掉新书（对应 app-storage「换源后重启」）

## 3. 换书源页面（online/change_source_page.dart）

- [x] 3.1 `changeSourceSearchProvider` 和页面的候选列表（D2）：
  - 打开时用书名搜索，读一次书架上所有书的地址
  - 候选取合并键等于这本书的 `MergedBook.results`
  - 每一项显示书源名和最新章节名，地址相同的标「当前」，在书架上的标「已在书架」，这两种都不能点
  - 进度、停止、没有可搜索书源时的提示，照搬搜索页的写法：搜索页的进度条改成公开的 `SearchProgress`，两个页面共用

  验证：新建 `test/online/change_source_page_test.dart`，用 FakeEngine 覆盖 bookshelf 规格的这几个场景：
  - 只列同名同作者的结果
  - 当前书源和已在书架的不能选
  - 离开时停止搜索：断言 `engine.batches` 里的批次已停止
  - 没有可搜索书源时的提示
- [x] 3.2 选中候选后的流程（D3、D4、D5）：
  - 禁用列表，依次执行 `bookInfo`、`chapterList`
  - 用 `shelfBookOf`、`tocUpdateOf` 组出新书，带上旧书的 `addedAt`、`lastReadAt`
  - 进度：读过的书用 `alignChapter` 的结果，`matched` 为假时章内位置归零；没读过的保持初始进度
  - 调用 `changeSource`，然后 `pop(newBookUrl)`
  - 失败时在这个候选下面显示原因，解除禁用
  - 加载中途返回时不写入

  验证：`change_source_page_test.dart` 覆盖：
  - 「换源成功」：书架上只有一本、顺序不变、显示新书源的最新章节，打开阅读页停在对齐到的章节
  - 「换源失败保持原样」：失败后数据库里还是旧书，再选另一个候选能成功
  - 「书源已删除的书」
  - 「没读过的书」
  - 「新书源已缓存的正文保留」：换源后读第 1 章，`engine.calls` 里没有这一章的 content 调用
  - 「书源级状态不变」：source_kv 的行不变

## 4. 入口

- [x] 4.1 书架菜单加一项「换书源」：放在「详情」和「移出书架」之间，打开 `ChangeSourcePage`，返回地址不为空时弹出 SnackBar「已换到 某某书源」（D1）。验证：`test/bookshelf/bookshelf_page_test.dart` 新增用例：
  - 从菜单进入换书源，换源成功后回到书架，能看到 SnackBar 和新书源的最新章节
  - 原来的「更新失败」标记不再显示
- [x] 4.2 从书架打开的详情页显示「换书源」按钮，成功后把 `_bookUrl` 换成新地址（D6）；搜索模式的按钮不变。验证：`test/online/book_detail_page_test.dart` 新增 book-detail 规格「从书架打开时换源」的用例：显示新书源名和目录，仍标明已在书架；原有用例全部通过。
- [x] 4.3 模块边界：确认 `library/relocate.dart` 和 `storage/` 不引用 `rule_engine`。验证：`test/module_boundary_test.dart` 通过。

## 5. 端到端与全量检查

- [x] 5.1 `integration_test/app_flow_test.dart`：
  - 本地服务器加第二个书源，书名和作者相同，目录前面多一个卷，章节名的写法不同
  - 在已有流程之后补一段：读到第 2 章 → 回书架换到第二个书源 → 打开后停在对齐到的那一章、同一位置

  验证：`-d macos` 和 `-d emulator-5554` 都通过。
- [x] 5.2 全量测试：带 `QUICKJS_NG_FFI_LIB` 跑 `flutter test`，再跑 `flutter analyze`。验证：测试全部通过，没有新的警告。

## 6. 文档

- [x] 6.1 PRD 4.3 节「书架上的书换书源」的状态改为已完成；第七节第 5 步记下这一项已完成。验证：通读一遍，和实现一致。
- [x] 6.2 README 目录表里 `app/` 的说明补上「书架换书源」。验证：通读一遍，和实现一致。
