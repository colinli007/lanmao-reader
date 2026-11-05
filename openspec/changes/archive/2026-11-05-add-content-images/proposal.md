## Why

正文里的图片现在显示成「[图片]」。轻小说的插图、有些网站用小图代替部分汉字防采集，这些都看不到。PRD 4.5 节把「正文图片」列为 P1，还没有开始做。用户 2026-11-04 决定先在模拟器上把功能做完，这是其中的第三项；行内小图和看大图也一起做。

## What Changes

做法照 legado-E 的 `TextChapterLayout.kt`（`setTypeImage`）、`ImageProvider.kt`、`BookHelp.saveImage`、`ImageUtils.decode`：

- **下载**：正文链路已经把 `<img>` 的地址转成绝对地址并保留 `,{选项}`。打开一章时，先下载这一章的图片再排版（Legado 也是排版时等图片，要先知道尺寸才能分页）。
  - 按书源下载：带书源的请求头和 Cookie，支持 `,{选项}`；`data:` 地址直接解码。
  - 书源有 `ruleContent.imageDecode` 时，用它处理下载到的字节（`book`、`result` 是字节、`src`），返回值是图片。
  - 同一章的图片并发下载；失败的显示「图片加载失败」的占位，下次打开这一章时重试。
- **缓存**：下载到的图片和正文一起缓存，算在「正文缓存」的大小里，清除正文缓存、移出书架、换书源时和正文一起删除。
- **显示方式**：每张图的样式取地址选项里的 `style`，没有时取书源的 `ruleContent.imageStyle`。
  - 行内（`TEXT`，或者没指定样式、图片小于 80×80）：像一个字一样嵌在文字里，宽一个字，高按比例，在行内垂直居中。
  - 单独成段：前后的文字各自成段，图片水平居中。
    - 默认：原始大小，比正文宽就缩到正文宽，比一页高就缩到一页高。
    - `FULL`：铺满正文宽度，比一页高就缩到一页高。
    - `SINGLE`：同 `FULL`，独占一页，垂直居中。
  - 地址选项里的 `width`（像素或百分比）按比例改变大小。
  - 一张图在阅读进度里算 1 个字。
- **看大图**：长按正文里的图片，打开全屏大图，双指缩放，点一下关闭。点击仍然是翻页和打开菜单。
- **不做**：
  - 图片地址选项里的 `click`（点图片执行书源 JS）。
  - Legado 在阅读菜单里切换图片样式。
  - 保存图片到相册。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `book-chains`：新增「正文图片」：按书源下载一张图片，执行 `imageDecode`。
- `reader`：「正文排版」里的图片改成按「正文图片」显示；新增「正文图片」「看大图」。
- `app-storage`：「落盘的数据」「清除正文缓存」包括正文图片。
- `settings`：「正文缓存大小」包括图片的字节数。

## Impact

- **rule_engine**：新增取图片的链路和 worker 任务（`imageTask`）；`SourceJs` 加执行 `imageDecode` 的入口；读 `imageStyle`。
- **app/lib/online/**：`SourceEngine.image`、`OnlineContentSource.loadImage`。
- **app/lib/library/content_source.dart**：`BookContentSource` 加 `loadImage`。
- **app/lib/storage/database.dart**：新表 `content_images`，schemaVersion 3 → 4；和正文一起删除、统计。
- **app/lib/reader/**：
  - `chapter_format.dart`：保留图片地址，段落带上图片。
  - 新增 `content_images.dart`：下载、量尺寸、按需解码、内存缓存。
  - `layout/chapter_layout.dart`：图片段、行内占位、`SINGLE` 独占一页，画图片，按位置找图片。
  - `paged/paged_view.dart`、`scroll/scroll_view.dart`：长按看大图；图片解码好以后重画。
  - 新增 `image_viewer_page.dart`：全屏大图。
- **测试**：引擎取图片和 `imageDecode`；格式化、排版（图片段、行内、分页、偏移）；存储和清理；阅读页长按；Android 模拟器上用带插图的书源走一遍。
