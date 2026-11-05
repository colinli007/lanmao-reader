## Context

- **搜索链路**：`chains.dart` 的 `_analyzeBookList` 按 `ruleSearch` 解析书籍列表。搜索地址是详情页（`bookUrlPattern`）或列表为空时，按详情页解析成一个结果。搜索分两段在 worker 里执行，请求在主 isolate 上发出。
- **书源级 JS**：`SourceJs.evalSource(task, code)`，`java`、`source` 是书源对象，`baseUrl` 是书源地址。书源 `header` 的 JS 就用它。MD3 的 `BaseSource.evalJS` 是同一个上下文。
- **详情页**：`BookDetailPage.search(MergedBook)` 接收合并项，可以只有一个书源的结果。
- **外壳**：`AppShell` 有书架、设置两个 tab；书架用 `Offstage` 常驻，设置页只在选中时构建。

MD3 和 Legado：
- `BookSource.exploreKinds()`：
  - `exploreUrl` 以 `<js>`、`@js:` 开头（不区分大小写）时，用书源的 `evalJS` 执行，另外注入 `infoMap`。结果 `toString().trim()`，存进磁盘缓存（键是书源地址加发现地址的 MD5），直到手动刷新。
  - 结果是 JSON 数组时按 `ExploreKind` 解析（GSON 宽松模式）。否则按正则 `(&&|\n)+` 拆开，每段按 `::` 拆成标题和地址。
  - 出错时只有一个分类，标题是 `ERROR:原因`。
- `ExploreKind`：`title`、`url`、`type`（默认 `url`）、`style`。MD3 多了 `action`、`chars`、`default`、`viewName` 和 `text`、`button`、`toggle`、`select` 四种类型。
- `FlexChildStyle`：`layout_flexGrow`（默认 0）、`layout_flexShrink`（1）、`layout_alignSelf`、`layout_flexBasisPercent`（-1）、`layout_wrapBefore`（false）。
- `WebBook.exploreBook`：按分类地址、页码构造请求（书源地址作 baseUrl），执行 `loginCheckJs`。然后 `analyzeBookList(isSearch = false)`：
  - 不判断 `bookUrlPattern`。
  - 规则是 `ruleExplore`，它的 `bookList` 为空时用 `ruleSearch`。
  - 列表为空且 `bookUrlPattern` 为空时，按详情页解析，和搜索相同。
- 发现页（Legado 3.25）：
  - 书源列表只显示 `enabledExplore` 为真、有发现地址的书源。可以按名称、分组筛选。点一个书源展开它的分类，同时只展开一个。
  - 分类放在 FlexboxLayout 里（横向、换行、内边距 3dp，分隔是 8dp 的空白、只在中间）。每个分类是一个 TextView：外边距 3dp，左右内边距 12dp，单行，14sp。
  - 没有地址的分类不能点。
- 分类书籍页（Legado `ExploreShowActivity`）：
  - 30 秒超时。
  - 每取到一页，页码加一。
  - 这一页没有书，或者第一本和最后一本都已经在列表里时，算到底了。

合集 1329 的 320 个书源：
- 217 个有发现地址：144 个 JSON 数组、52 个 JS、21 个文本。
- JSON 数组里的 2624 个分类全是 `url` 类型，其中 2588 个写了样式。宽度比例最常见的是 0.25（1300 个）和 0.2（718 个）。
- 只有 1 个 JS 生成了 `select` 类型，1 个用到 `infoMap`。

## Goals / Non-Goals

**Goals：** 按书源的分类浏览书籍，分类排版和 Legado 一样，JS 生成的分类能用，分页加载，点书进入详情。

**Non-Goals：**
- MD3 的交互式分类和 `infoMap`。
- 书源菜单、刷新分类、分类结果存磁盘。
- 不是文本的书源。

## Decisions

### D1 引擎：分类解析和发现链路都在 worker 里

发现分类可能执行 JS，JS 里可能发请求（`java.ajax`）。JSON 数组的解析放哪都行，但两种来源走同一条路更简单。所以 `getExploreKinds(env, source)` 整个在 worker 里执行，结果是普通 Dart 对象：

- `ExploreKind`：`title`、`url`（可为空）、`type`（默认 `url`）、`style`。
- `FlexStyle`：`grow`、`shrink`、`basisPercent`、`wrapBefore`。
- 数值可以是数字，也可以是数字文本（GSON 宽松模式也能读）。读不出时用默认值。

解析规则和 MD3 一样：
- JS 结果先 `trim`。
- 以 `[` 开头、`]` 结尾时按宽松 JSON 数组解析，数组里不是对象的项跳过。解析失败时抛出错误。
- 否则按 `(&&|\n)+` 拆开，每段按 `::` 拆，取前两段作标题和地址。

出错时抛出错误，由界面显示原因和「重试」，不像 MD3 那样做成一个 `ERROR:` 分类：错误是给人看的状态，不是可以点的分类。

`exploreBooks(env, source, url, page)`：

- 用 `buildSourceRequest` 构造请求，baseUrl 是书源地址，`ruleData` 是本次链路的变量。
- 发出请求，执行 `loginCheckJs`。
- 用 `_analyzeBookList` 的发现模式解析。发现模式不判断 `bookUrlPattern`，规则组按 MD3 选。

发现链路是交互任务，用户在等，所以直接提交，不经批量限流器。超时 30 秒（Legado 相同）。

不像搜索那样分两段：发现一次只请求一个书源，不存在多个书源同时等网络占满 worker 的问题。

### D2 能出现在发现页的书源

条件是：启用、文本类、`enabledExplore` 不是 `false`、发现地址不为空。

和 Legado 的区别：Legado 只看 `enabledExplore`，不看 `enabled`。本 app 只有一个「启用」开关，停用一个书源的意思就是「不用它」，所以发现页也不显示它。只显示文本类书源，和搜索相同，因为 app 只能读文本。

### D3 分类在这次运行里只算一次

每个书源的分类是 `exploreKindsProvider`，按（书源地址，发现地址）缓存，不会自动释放。

- 第一次展开时计算，之后再展开直接显示。
- 出错时显示原因，点「重试」重新计算。
- 发现地址变了（重新导入），键也就变了，会重新计算。

MD3 把 JS 的结果存到磁盘，直到手动刷新。这里不存：JS 的结果可能依赖网络或书源变量，重启后重新执行一次，代价是一次请求，省掉了刷新菜单和磁盘缓存。

### D4 分类排版照 FlexboxLayout

几乎所有分类都写了样式，书源作者是对着 Legado 的显示效果调的。所以按 Legado 的实际尺寸算，不照 MD3 Compose 版的栅格近似：

- 容器左右各留 3dp 内边距，可用宽度记为 W。每个分类四周有 3dp 外边距。同一行相邻的分类之间、相邻的两行之间还有 8dp 的分隔（`dividerDrawable` 是 8dp 的空白，`showDivider` 是 middle），所以两个分类的边相距 14dp。
- 分类的基础宽度：
  - `basisPercent` 不小于 0 时，基础宽度是 W 乘以它。
  - 否则是文字宽度加左右各 12dp 内边距。
- 按顺序排进行里。遇到下面两种情况换行（当前行不为空时）：
  - `wrapBefore` 为真。
  - 当前行加上这个分类（基础宽度加 6dp 外边距，再加和前一个分类之间 8dp 的分隔）会超过 W。
- 每行排完后：
  - 有剩余宽度时，按 `grow` 的比例分给这一行的分类。
  - 超出时（只会是单个分类比 W 还宽），按 `shrink` 乘以基础宽度的比例压缩。
- 所以在 360dp 宽的屏幕上，0.25 的分类一行排 3 个，剩余宽度由伸展补满；0.2 的一行排 4 个。这和 Legado 里看到的一样。

计算写成纯函数 `flexRows(items, width)`，返回每行每个分类的宽度，单独测试。

显示：
- 有地址的 `url` 分类是浅灰底的圆角胶囊，单行，文字居中、超出省略。点了进入分类书籍页。
- 没有地址的是小标题：灰字、不加底色，不能点。
- 其余类型（`text`、`button`、`toggle`、`select`）是灰色胶囊，不能点。

### D5 发现 tab

外壳加第二个 tab「发现」，图标是指南针。和书架一样用 `Offstage` 常驻，切走再切回时筛选、展开的书源和滚动位置都还在。

页面：
- 顶栏是大标题「发现」。
- 下面是筛选框，提示「筛选书源」，按书源名或分组包含筛选（不区分大小写）。
- 书源一行一个：名称，右边是展开或收起的箭头。点一行展开它的分类，再点收起；展开另一个时收起之前的。
- 展开时，分类还在计算就显示转圈；计算完显示分类；分类是空的显示「没有分类」。
- 没有符合 D2 的书源时，显示「没有可以发现的书源，先在「设置 → 书源」里导入或启用」。

### D6 分类书籍页

`ExploreBooksPage(source, kind)`，标题是分类名。页面自己管理状态：书、下一页的页码、是否在加载、错误、是否到底。

- 打开时取第 1 页。
- 列表最后一项是页脚，页脚出现时取下一页（Legado 的「加载更多」）。第一页太短、填不满屏幕时，也会接着取。
- 去掉书籍地址已经在列表里的书。这一页没有新书时算到底，页脚显示「没有更多了」；第 1 页就没有书时显示「没有书」。
- 出错时页脚显示原因和「重试」。

每本书一行：封面、书名；作者和最新章节；简介最多 2 行。点一本书时，用这一个书源的结果建一个合并项，打开 `BookDetailPage.search`，后面的流程（详情、目录、加入书架、换源）和搜索相同。

### D7 交互式分类不做

MD3 扩展的四种控件需要 `infoMap`（按书源存的键值）、`action` JS 和刷新分类的机制，320 个书源里只有 1 个在用。这次只显示成灰色、不能点，不影响同一个书源的其它分类。

## Risks / Trade-offs

- JS 生成分类时可能请求网络，第一次展开会慢一些，每次重启后第一次展开都要重新执行。
- 用 `infoMap` 的 JS 会因为变量未定义而出错，显示原因和「重试」。
- 合集 1329 里有 12 个书源的发现 JS 用了 `[title,id]=>` 这种不带括号的解构箭头函数，Rhino 认、QuickJS 报语法错误；还有一些直接用 Java 类（`org.jsoup`）。这些书源展开时显示出错原因。语法兼容属于 source-js，不在这次改。
