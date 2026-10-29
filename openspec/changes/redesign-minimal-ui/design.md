## Context

动机和范围见 proposal.md，行为要求见 `specs/`。视觉参考是花火阅读 1.3.3（本地文档 `docs/竞品分析-花火阅读-2026-10-28.md`，不入库）。

### 现状（main）

- **主题**：`app.dart` 用 `ThemeData(colorSchemeSeed: Colors.teal)`，各页面用 Material 默认组件：`AppBar`、`ListTile`、`PopupMenuButton`、`SegmentedButton`、`Slider`。
- **入口**：书架是首页，顶栏有更新目录、搜索、书源、设置四个按钮，没有底部 tab。
- **书架**：`ListView` 加 `ListTile`。行尾是未读角标和 ••• 菜单（详情、换书源、移出书架）；更新失败显示在副标题里，点了用 SnackBar 显示原因。
- **详情页**：信息和整个目录列表在同一页；从书架打开时有「换书源」按钮。
- **阅读页**：
  - 菜单是 `AppBar`（书名、章节名）加底栏（上一章、目录、设置、下一章）。
  - 目录是 `Scaffold` 的抽屉（`chapter_list.dart`）。
  - 设置是 `showModalBottomSheet` 弹出的 `_SettingsSheet`：5 个 `_SettingSlider`、2 个 `SegmentedButton`、2 个 `SwitchListTile`。
- **设置页**：替换净化规则、正文缓存、关于，统计用 `contentCacheStatsProvider`（`autoDispose`，进入页面时统计）。
- **影院分支**（`feat/redesign-cinema-ui`，不合并）里能复用的功能代码：
  - `TocPage`：卷分组、固定行高算滚动位置、正倒序、回到当前。
  - `AppDatabase.watchCachedChapterUrls`。
  - `SourceEntry.groups`：按 `[,;，；]` 拆分组。
  - `ui/icons.dart`：lucide 码位常量，加上 `assets/fonts/lucide.ttf`。

### 约束

- 阅读页的排版、分页、翻页、进度逻辑这次不动：页眉页脚、`PagePainter`、`ChapterWindow` 都不改，金样图不受影响。
- `ReaderSettings` 的存储键和格式不变，不做数据迁移。
- 组件内能自己完成的事不通过参数传进去（用户的开发规范）。读写阅读设置的面板直接 `ref` 读写 `readerSettingsProvider`，不由阅读页把回调传给它们。

## Goals / Non-Goals

**Goals:**

- 颜色、字号、间距、圆角集中在一处定义，页面里不散落魔法数，深浅两套从同一组定义派生。
- 新界面只覆盖已实现的功能；每个入口点下去都有真实行为。
- 阅读菜单的面板切换只是界面状态，不影响正文的手势和点击区域逻辑。

**Non-Goals:**

- 不改阅读正文的配色（三套 `ReaderTheme` 的颜色不变）和排版。
- 不做平板或横屏的专门布局；只保证 macOS 宽窗口下宫格列数合理。
- 不做动画转场，只用平台默认的页面切换。

## Decisions

### D1 外壳：书架常驻，设置只在选中时构建

`AppShell` 是一个 `Scaffold`，`body` 按选中的 tab 显示，底部是自绘的两项 tab 栏：线条图标加小字，选中项用强调色。

- 书架放在 `Offstage` 里常驻，切走再切回时，滚动位置和进行中的更新目录都还在。这是 app-shell「底部 tab」的要求。
- 设置页只在选中时构建。`contentCacheStatsProvider` 是 `autoDispose`，页面重建就会重新统计，自然满足 settings「每次切到设置 tab 时重新统计」，不用在外壳里额外调用 `invalidate`。

备选方案：

- 两个 tab 都放进 `IndexedStack`：设置页一直活着，切回来时要靠外壳 `invalidate` 统计，等于外壳替设置页管它的数据。不选。
- Material 的 `NavigationBar`：自带胶囊形指示器和 64dp 高度，跟极简的样式不符，改样式的量和自绘差不多。不选。

搜索、详情、阅读等页面照旧 `Navigator.push` 到根导航器，盖住底部 tab。

### D2 视觉定义：`app/lib/ui/`

| 文件 | 内容 |
|---|---|
| `tokens.dart` | 颜色、字号、间距、圆角常量；深浅两套颜色放在一个 `ThemeExtension`（`AppColors`）里 |
| `theme.dart` | 由 `AppColors` 构造 `ThemeData`：`ColorScheme.primary` 设为强调色，`AppBar`、`ListTile`、`Switch`、`FilledButton` 等组件主题去掉阴影、改圆角 |
| `icons.dart` | 从影院分支搬 lucide 码位常量，只保留这次用到的 |
| `widgets.dart` | 几个通用组件：分组卡片（`SettingsGroup`）、选项单（`showActionSheet`）、胶囊按钮、步进器（`ValueStepper`，避开 Material 的 `Stepper`）、预设选择（`PresetPicker`）、弹框（`AppDialog` 和 `showConfirmDialog`、`showMessageDialog`，见下） |

颜色：

| 名字 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| accent | `#2F5D50` | `#8CBFAE` | 主按钮、选中态、开关、tab |
| background | `#FFFFFF` | `#121212` | 页面底色 |
| surface | `#FFFFFF` | `#1E1E1E` | 弹框、底部弹层、弹出菜单的底色；深色下比页面亮一档，盖上遮罩以后才看得出边界 |
| fill | `#F5F5F5` | `#2A2A2A` | 卡片、次要按钮、输入框 |
| groupedBackground | `#F5F5F5` | `#000000` | 设置页这类分组卡片页面的底色，卡片用 background |
| textPrimary | `#1F1F1F` | `#E6E6E6` | |
| textSecondary | `#767676` | `#9A9A9A` | 状态、说明 |
| danger | `#D93025` | `#F28B82` | 「更新失败」、移出书架 |

- 深色下的强调色调亮了：`#2F5D50` 放在 `#121212` 上对比度不够。按 WCAG AA（正文 4.5:1）核对过：强调色在白底上 7.49、在深色底上 9.08；次要文字在白底上 4.54；深色下在 `#2A2A2A` 上 5.1（浅色原定的 `#8A8A8A` 只有 3.45，改成了 `#767676`；深色原定的 `#8A8A8A` 在弹框里的 `fill` 上只有 4.16，改成了 `#9A9A9A`）。
- 页面里 MUST 通过 `AppColors.of(context)` 取色，不直接写色值。

弹框：项目里的确认、提示、输入弹框（共 10 个）统一用 `AppDialog`，居中、标题居中、说明是灰字，底部两个等宽胶囊按钮（「取消」用浅灰，确认用强调色，删除、移出、清除这类危险操作用危险色）。用户在居中弹框和底部弹层之间选了居中弹框。

备选：继续用 `colorSchemeSeed` 生成整套 Material 3 配色。生成的颜色带色调，卡片和背景都会染上绿，做不出白底灰卡的效果。不选。

### D3 书架

- `GridView` 用 `SliverGridDelegateWithMaxCrossAxisExtent`，最大宽度取 140：手机竖屏（约 390 宽，扣掉左右 20 的边距）正好三列，macOS 宽窗口自动加列，封面宽度变化不大。
- 封面高宽比 4:3，沿用 `BookCover`。占位封面改成浅灰底，上面写书名，不再是一个图标。
- 长按用 D2 的 `showActionSheet`。更新失败的书多一项「失败原因」，选了弹对话框显示原因，不再用 SnackBar。
- 下拉刷新沿用 `RefreshIndicator`。macOS 顶栏的「更新目录」按钮按 `defaultTargetPlatform == TargetPlatform.macOS` 显示。

### D4 目录页：从影院分支搬功能，样式重写

`app/lib/reader/toc_page.dart` 保留影院版的这些逻辑：

- 构造参数 `book`、`chapters`、`current`；点一章时 `pop` 这一章的下标。
- 固定行高，打开时直接算出初始滚动位置，2000 章也不用逐行测量（`toc_perf_test` 守着这一点）。
- 正倒序。
- 回到当前。

去掉的：

- 模糊封面背景、tab
- 卷序号和章节范围：规格没要求，卷标题只显示卷名
- 「读到这里」大行高

已缓存标记用 `watchCachedChapterUrls(bookUrl)` 的 `StreamProvider.family`，目录页自己 `ref.watch`，不由打开它的页面传进来。

阅读页和详情页都用 `Navigator.push<int>` 打开它：

- 阅读页拿到下标后调用 `_go(index)`。
- 详情页拿到下标后，带着 `startAt` 打开阅读页。

`chapter_list.dart` 和阅读页的抽屉删掉。

### D5 阅读菜单：一个枚举管面板

```dart
enum ReaderPanel { progress, appearance, layout }
```

- `_ReaderPageState` 新增 `ReaderPanel? _panel`。
  - 点底栏图标：等于当前面板时设为 `null`，否则设为这个面板。
  - 隐藏菜单时一起清空 `_panel`。
- 菜单显示、隐藏仍由现有的 `_menu` 控制，正文的点击区域判断不变：菜单显示时点正文只收起菜单。
- 底栏和面板放在一个 `Column` 里，面板在上、底栏在下，底栏的位置不随面板变化。
- 顶栏只有返回。章节名移到进度面板里。

三个面板是独立的 widget（`app/lib/reader/menu/`）：

- `ProgressPanel`：需要当前章节和跳转。它拿 `ChapterWindow`，跳转调用 `window.open(index)`，而不是由阅读页传一个 `onJump` 回调。`ChapterWindow` 本来就是阅读页传给分页、滚动视图的共享对象，面板拿到它跟视图拿到它是一样的用法。
  - 进度条用 `Slider`，`divisions` 等于非卷章节数减一，值是第几个非卷章节。拖动中只更新面板自己的状态，用来显示目标章节名；`onChangeEnd` 才跳转。
  - 上一章、下一章用 `window.neighbor`。
- `AppearancePanel`、`LayoutPanel`：直接读写 `readerSettingsProvider`。

### D6 预设和步进

`ReaderSettings` 加两组预设常量：

```dart
static const lineHeightPresets = [1.5, 1.8, 2.2];
static const paragraphSpacingPresets = [0.3, 0.6, 1.0];
```

- 选中判断：值和预设相等。行距、段距落盘时就按一位小数格式化，读回来的值和预设能精确比较。
- `fromMap` 的范围（1.0–3.0、0–2）不变，改版前存下的值照常读进来。没有预设与之相等时，不选中任何一项。
- 预设按钮显示三条疏密不同的横线图标，`Semantics` 标签是紧凑、适中、宽松。
- 步进器 `ValueStepper(value, min, max, step, onChanged)`：到边界时对应按钮禁用。字号、缩进、边距共用。参数形式跟现有的 `_SettingSlider` 一样，由调用处传 `onChanged`，因为它是通用控件，不知道自己改的是哪个字段。

备选：保留滑块，外观换掉。用户确认了改成预设和步进。

### D7 设置页和阅读设置页

- 设置页用 `groupedBackground` 底色，加三组 `SettingsGroup` 卡片：
  - 书源、替换净化规则
  - 阅读设置、正文缓存
  - 关于
- 正文缓存那一项保留现在的统计和清除逻辑，只换外观。
- `reader_settings_page.dart` 有两个开关，直接读写 `readerSettingsProvider`。
- 书源列表的入口从书架顶栏移到这里，书源日志的入口留在书源列表页顶栏。

### D8 书源列表的分组和统计

- 搬 `SourceEntry.groups`。
- 列表页顶部依次是：子串筛选框、分组的横向胶囊列表（「全部」加各分组，「未分组」在最后；没有任何分组时不显示）、「已启用 7 / 共 10」。
- 筛选条件只是列表页的状态，不落盘。

### D9 图标和字体

- 打包 `assets/fonts/lucide.ttf`（约 0.9MB，release 构建按用到的码位裁剪），许可证 `LUCIDE_LICENSE.txt` 登记到 `LicenseRegistry`，和影院分支的做法一样。
- 不打包衬线字体，正文和界面都用系统字体。

## Risks / Trade-offs

- [组件测试大量依赖 `find.byTooltip`、`find.text` 找 Material 组件，改版后会大面积失效] → 新组件都带 `tooltip` 或 `Semantics` 标签，测试按标签找。阅读页的点击区域、分页、进度测试不碰菜单，不受影响。
- [`app_flow`、`real_sources` 集成测试的查找方式要跟着改] → 按 tasks 在 iOS 和 Android 模拟器上重跑。`real_sources` 和 `reading_soak` 留到真机阶段，和发布准备时一样。
- [行距、段距不能再连续调节，有用户会想要 2.0 这类值] → 改版前存下的值仍然生效。以后有人要，再在预设后面加「自定义」，不影响这次的结构。
- [深色模式下强调色的对比度] → D2 的色值实现时用对比度工具核对。
- [lucide 字体使安装包增加约 0.9MB] → 可以接受。影院分支连同衬线字体一起，arm64 APK 从 10.3MB 增加到 12.2MB；这次不带衬线字体，增加得更少。
- [宫格去掉了作者和最新章节名，书多时不容易区分同名书] → 同名书在书架上本来就少，长按「详情」能看到。以后要做宫格和列表切换时再加回列表模式（PRD 里是「以后」）。

## Migration Plan

- 不涉及数据迁移：阅读设置的键和格式不变，非预设的旧值继续生效。
- 在 `feat/redesign-minimal` 上开发，合并回 main 由用户决定。回滚就是不合并。
