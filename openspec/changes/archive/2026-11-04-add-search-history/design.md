## Context

搜索页（`search_page.dart`）现在是无状态组件，输入框不受控，提交时调用 `SearchController.search`。换书源页面（`change_source_page.dart`）用同一个 `SearchController` 类按书名搜候选，所以记历史不能放在控制器里。

参考实现是 legado-E（和官方 Legado 3.25 相同）：

- `SearchKeyword(word 主键, usage, lastUseTime)`。
- `saveSearchKey`：提交时调用，已有的 `usage + 1` 并更新时间，没有的插入 `usage = 1`。
- `upHistory(key)`：key 为空时 `ORDER BY lastUseTime DESC`，不为空时 `word LIKE '%key%' ORDER BY usage DESC`。
- 输入框内容变化（`onQueryTextChange`）时停止搜索并显示历史，提交时隐藏历史。
- 点击 `searchHistory` 填入并提交；长按 `deleteHistory` 删一条；「清除」确认后 `deleteAll`。

## Goals / Non-Goals

**Goals：** 行为和 Legado 一致；重启后历史还在；升级不丢数据。

**Non-Goals：** 书架匹配、历史条数上限、在其它页面使用历史。

## Decisions

### D1 存在新表里，不放进 settings

历史要按「包含输入的字」过滤、按次数或时间排序，并且在点击、删除后马上刷新。新表 `search_keywords(word TEXT 主键, usage INT, last_used DATETIME)` 可以直接用 SQL 排序过滤，用 drift 的 `watch()` 变成数据流，和书架、已缓存章节的写法一样（`shelfProvider`、`cachedChapterUrlsProvider`）。settings 表只在启动时读一次，存成一个 JSON 串的话要自己排序过滤，改动后也没有通知。

schemaVersion 2 → 3，`onUpgrade` 里 `from < 3` 时建表，和 v2 加 `replace_rules` 的写法一样。

### D2 显示历史还是结果，看最后一次操作是「改输入框」还是「提交」

结果区域显示什么，回答的是「用户现在是在输入，还是在看这次搜索的结果」。最直接的信号就是这两个事件本身：输入框的 `onChanged` 表示在输入，`onSubmitted` 和点历史词表示提交。页面里用一个布尔值记下最后一次是哪种，初始是「在输入」。不用「输入框的字和上次搜的词是否相同」来推断，那样把字改回去时会意外显示旧结果，也和 Legado 不一致。

改输入框时调用 `SearchController.stop()`，和 Legado 的 `viewModel.stop()` 一样：用户已经在输入新的词，旧的搜索没有必要继续占网络。已经出来的结果保留在控制器里，但不显示，下一次提交会整个替换掉。

### D3 记历史放在搜索页的提交里

只有搜索页的提交算用户的搜索历史；换书源页面用书名搜候选，不是用户输入的。所以写库放在搜索页（提交、点历史词）里，`SearchController` 不变。去掉首尾空白后为空的不记，和 book-search「发起搜索」的规则一致。没有可用书源时也记下，和 Legado 一样，因为用户确实搜了这个词。

### D4 列表的样子

「搜索历史」标题，右边「清除」；下面用 `Wrap` 排成一行行的标签（Legado 用 FlexboxLayoutManager，效果相同），整块可以滚动。没有任何历史时整块不显示，留空白，和 Legado 隐藏「清除」的做法一致。

## Risks / Trade-offs

- 改输入框就停止搜索：用户误碰输入框会中断搜索。Legado 也是这样，接受。
- 不限条数：用户长期使用后历史很多。Legado 相同；需要时可以「清除」。
