## 1. 基础（D1–D5）

- [x] 1.1 `lib/ui/cinema.dart`：颜色令牌、`serif()`、`sans()`、深色主题；`lib/ui/widgets.dart`：组件库里的共用组件和 `showNotDeveloped`；`lib/ui/icons.dart`：用到的 lucide 图标。
- [x] 1.2 衬线字体：`tool/subset_serif_font.py` 裁出 Noto Serif SC Black 的 GB2312 子集（7542 个字符，2.1MB），放在 `assets/fonts/`，OFL 许可证登记到「开源许可」。
- [x] 1.3 图标：只打包 lucide 的 `lucide.ttf`（ISC 许可证）。先用的是 `lucide_icons_flutter` 包，它另外带了 6 个不同粗细的图标字体，release 构建时裁不掉，多出约 3MB，改为只放这一个字体文件。
- [x] 1.4 `HomeShell`：底部 Tab、状态栏渐变；「我的」只在选中时构建。
- [x] 1.5 `app.dart` 换成深色主题和 `HomeShell`。

## 2. 页面（D6–D11）

- [x] 2.1 书架：继续阅读大图、追更中、全部书架的筛选和宫格、长按菜单；书架查询多返回非卷章节总数；macOS 顶栏的更新目录按钮。
- [x] 2.2 详情页：模糊背景、统计、主按钮、快捷操作、简介和标签、最新三章。
- [x] 2.3 目录页 `TocPage`：取代阅读页的抽屉和详情页的目录列表；新增 `watchCachedChapterUrls`；删除 `chapter_list.dart`。
- [x] 2.4 阅读菜单 `ReaderMenu`（夜墨和暖墨两版）、设置面板挪到 `reader_settings_sheet.dart`；阅读主题改为四种。
- [x] 2.5 转场 `openReader()` 和 `ReaderPage.introMenu`。
- [x] 2.6 书源页：启用数、分组、卡片列表、多选顶栏、免责声明；`SourceEntry.groups`。
- [x] 2.7 我的：四项设置，书源日志的入口从书源页挪过来。

## 3. 测试

- [x] 3.1 组件测试按新界面改查找方式，补上新场景：菜单自动收起和不再收起、进度条换章、日间夜间、暂未开发提示、目录的卷范围和已缓存标记和倒序、书架筛选读完、长按进详情、macOS 更新目录按钮、外壳深色、切回「我的」重新统计、书源分组和全选导出。羊皮主题的底色变了，重新生成了 3 张页面绘制的金样图。

  结果（2026-10-28）：`flutter test` 265 个通过（原来 254 个），`flutter analyze` 没有问题。
- [x] 3.2 集成测试跟着改：`app_flow`、`real_sources`、`toc_perf`、`reading_soak`。

  结果（2026-10-28）：
  - `app_flow`：iOS 模拟器（iPhone 17 Pro，iOS 26.3）、Android 模拟器（API 36）、macOS 上都通过。
  - `toc_perf`：Android 模拟器上通过（debug 构建，三项中位数 123ms、127ms、88ms）。macOS 上详情页那一段没有跑通，用户 2026-10-28 决定以 iOS、Android 为主，不在 macOS 上继续查。
  - `real_sources`、`reading_soak` 改了查找方式，这次没有跑（要真实书源和 1 小时），留到 4.2。
- [x] 3.3 在 iOS 模拟器和 Android 模拟器上用种子数据逐屏截图，对照设计稿检查。

  结果（2026-10-28）：改了几处：详情页和目录页背景模糊图的底边是硬边（模糊溢出没有裁剪）、分类标签被撑满整行、书源页的比例条高度是 0、目录页底部两个按钮在 402 宽的屏幕上放不下、页面滚上去以后内容和状态栏叠在一起。用系统衬线字体时 iOS 和 Android 上都显示成黑体，改为打包子集（D2）。

## 4. 收尾

- [x] 4.1 体积：按 `release.sh` 的参数（`--split-per-abi --target-platform android-arm64`）打 APK，12.2MB（改版前 10.3MB，多出来的基本是字体子集），在 20MB 上限以内。
- [ ] 4.2 真机：Android 真机（Redmi Note 14 Pro）和 iPhone 上走查一遍，重点看模糊效果是否掉帧（Risks 第 1 条）、安全区、字体；跑 `real_sources`。
- [x] 4.3 文档：PRD 和 v0.1.0 发布说明里的主题名、设置页入口；README 里没有要改的说法。
- [ ] 4.4 同步到主规格并归档；prepare-release 重新打包。
