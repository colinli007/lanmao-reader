## Why

每次搜索都要重新输入书名。PRD 4.2 节把「搜索历史」列为 P1，还没有开始做。用户 2026-11-04 决定先在模拟器上把功能做完，搜索历史是其中第一项。官方 Legado、legado-E、legado-with-MD3 都有搜索历史，做法相同，我们照着做。

## What Changes

做法照 legado-E 的 `SearchActivity.kt`、`SearchViewModel.kt`、`SearchKeywordDao.kt`：

- 在搜索页提交一个词时记下它：已有的使用次数加一，最后使用时间改成现在；没有的新加一条，次数为 1。换书源页面的搜索不记。
- 搜索页还没提交、或者提交后又改了输入框时，结果区域换成「搜索历史」：
  - 输入框为空：全部历史，最近用过的在前。
  - 输入框有字：包含这些字的历史，用得多的在前。
  - 改输入框时停止正在进行的搜索，和 Legado 一样。
- 点一个历史词：填进输入框并搜索。长按：删掉这一个，不用确认。「清除」：确认后删掉全部。
- 没有历史时不显示「搜索历史」这一块。
- 历史记录落盘，重启后还在。
- **不做**：
  - Legado 在搜索页同时列出书架上书名匹配的书。
  - 历史条数上限：Legado 也没有。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `book-search`：新增「搜索历史」要求。
- `app-storage`：「落盘的数据」加上搜索历史；从没有搜索历史的版本升级时数据都在。

## Impact

- **app/lib/storage/database.dart**：新表 `search_keywords`（词、使用次数、最后使用时间），schemaVersion 2 → 3，升级时建表；读写方法。
- **app/lib/online/search_page.dart**：改成有状态的组件，输入框受控；显示历史、点击、长按、清除。
- **测试**：数据库的读写和升级、搜索页的 widget 测试；Android 模拟器上走一遍。
