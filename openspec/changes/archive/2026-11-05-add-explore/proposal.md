## Why

现在只能按书名、作者搜书，不能像 Legado 那样按书源的分类、排行浏览。PRD 4.2 节把「发现页（`exploreUrl`、`ruleExplore`）」列为 P1，还没有开始做。合集 1329 的 320 个书源里有 217 个写了发现地址（其中 52 个由 JS 生成），是用得很多的功能。用户 2026-11-04 决定先在模拟器上把功能做完，这是第五项。用户 2026-11-05 选定：底部加「发现」tab；分类按书源写的样式排；MD3 扩展的交互式分类这次先不做。

## What Changes

做法参考 legado-with-MD3 的 `BookSourceExtensions.exploreKinds`、`WebBook.exploreBook`、`BookList.analyzeBookList`，和 Legado 3.25 的发现页布局（`item_find_book`、`item_fillet_text`）：

- **规则引擎**：
  - 书源加 `exploreUrl`、`enabledExplore`、`ruleExplore`。
  - 发现分类：`exploreUrl` 是 JSON 数组时按分类对象解析；以 `<js>`、`@js:` 开头时先用书源级的 JS 上下文执行，结果再按 JSON 数组或文本解析；文本按 `&&` 和换行拆开，每段 `标题::地址`。
  - 发现链路：按分类地址和页码请求，解析书籍列表。规则用 `ruleExplore`，它的 `bookList` 为空时用 `ruleSearch`；不判断 `bookUrlPattern`。其余和搜索相同。
- **发现 tab**：底部变成书架、发现、设置三个 tab。
  - 列出启用的、文本类的、写了发现地址的书源，顶上可以按书源名和分组筛选。
  - 点一个书源展开它的分类，同时只展开一个。分类在这次运行里只算一次，出错时显示原因和「重试」。
  - 分类按书源写的样式排：宽度比例、伸展、强制换行，边距和 Legado 一样；没有地址的分类显示成小标题；交互式分类（输入框、下拉、开关、按钮）显示成灰色、不能点。
- **分类书籍页**：点一个分类进入，标题是分类名。
  - 先取第 1 页，滑到底部时取下一页；去掉已经有的书，没有新书时显示「没有更多了」。
  - 出错时显示原因和「重试」。
  - 点一本书打开详情页，和从搜索结果打开一样。
- **不做**：
  - MD3 的交互式分类和 `infoMap`。
  - 发现页的书源菜单（编辑、置顶、登录、删除）和刷新分类。
  - 把 JS 生成的分类存到磁盘；重启后重新执行。
  - 漫画、音频等不是文本的书源。

## Capabilities

### New Capabilities

- `explore`：发现 tab 的书源列表、筛选、分类和排版、分类书籍页。

### Modified Capabilities

- `book-chains`：加「发现分类」「发现」两条链路。
- `app-shell`：底部 tab 从两个变成书架、发现、设置三个。

## Impact

- **packages/rule_engine**：
  - `book_source.dart`：`exploreUrl`、`enabledExplore`、`ruleExplore`。
  - 新增 `chain/explore.dart`：`ExploreKind`、`FlexStyle`，`getExploreKinds`、`exploreBooks`。
  - `chains.dart`：书籍列表解析加发现模式。
  - `tasks.dart`：`exploreKindsTask`、`exploreTask`。
- **app/lib/online/**：
  - `source_engine.dart`：`exploreKinds`、`explore`。
  - `source_repository.dart`：`SourceEntry.explorable`。
  - 新增 `explore_page.dart`（发现 tab）、`explore_kinds.dart`（分类排版）、`explore_books_page.dart`（分类书籍页）。
- **app/lib/app_shell.dart**：加「发现」tab。
- **app/lib/ui/icons.dart**：加 compass 图标。
- **测试**：引擎的分类解析和发现链路；排版计算；发现页和分类书籍页；Android 模拟器上用合集 1329 的书源走查。
