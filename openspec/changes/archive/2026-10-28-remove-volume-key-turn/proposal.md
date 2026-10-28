## Why

「音量键翻页」是 complete-reader-settings（2026-10-25）加的，只在 Android 上有。用户 2026-10-28 在真机上用过以后，决定删掉它，原因是：这个功能完全没有用，太鸡肋。

第一版还没发布，现在删，以后不用为它维护代码、测试和设置项，也不会出现「Android 有、iOS 和 macOS 没有」的差别。

## What Changes

- **BREAKING（只影响开发中的版本，还没对外发布过）**：删除 Android 音量键翻页。阅读页里，音量键始终只调系统音量，任何翻页方式下都不翻页。
- 阅读设置面板去掉「音量键翻页」开关；阅读设置不再有这一项，也不再读写 `reader.volumeKeyTurn`。
- 分页视图和滚动视图退回加音量键翻页之前的样子：不再包一层 `Focus` 处理按键；滚动视图里专门给点击和按键共用而抽出来的 `_scrollScreen`，重新并回点击处理。
- 文档同步：PRD 4.5 节把这一项标为已删除并写明原因；第七节第 7 步、第八节第 4 条里的说法跟着改；README、v0.1.0 的发布说明去掉这一项。
- **不做**：
  - 不做键盘翻页、耳机线控翻页等替代功能。
  - 不清理开发机数据库里已经存过的 `reader.volumeKeyTurn`：读设置时不认识的键本来就会被忽略，而且这个版本没有对外发布过，没有用户数据需要迁移。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `reader`：
  - 删除「音量键翻页」需求。
  - 修改「阅读设置」：去掉「音量键翻页」这一项。

## Impact

- **代码**（都在 `app/lib/reader/`）：
  - 删除 `volume_keys.dart`。
  - `reader_settings.dart`：删掉 `volumeKeyTurn` 字段、它的键、默认值和 `copyWith`、`fromMap`、`toMap` 里的处理。
  - `paged/paged_view.dart`、`scroll/scroll_view.dart`：删掉 `volumeKeyTurn` 参数和 `Focus` 包装；滚动视图的 `_scrollScreen` 并回 `_onTapUp`。
  - `reader_page.dart`：不再给两个视图传 `volumeKeyTurn`；设置面板删掉只在 Android 上显示的开关。
- **测试**：
  - `test/reader/reader_page_test.dart`：删掉「音量键翻页」一组用例和「只在 Android 上显示」的用例；设置面板落盘的用例去掉这一项。
  - `test/reader/reader_settings_test.dart`、`test/reader/paged/paged_view_test.dart`：去掉 `volumeKeyTurn`。
  - 不为「音量键不翻页」新写测试：这个功能已经不存在了；删没删干净，看 `flutter analyze` 和全仓搜索里还有没有引用就够了。
- **原生代码**：没有。音量键翻页当初就没有写原生代码（complete-reader-settings 设计 D3）。
- **依赖**：无变化。
- **和 prepare-release 的关系**：prepare-release 任务 6.6 里的音量键检查不用做了；这个 change 做完、归档以后，prepare-release 要重新打包，v0.1.0 发布的包里不含这个功能。
