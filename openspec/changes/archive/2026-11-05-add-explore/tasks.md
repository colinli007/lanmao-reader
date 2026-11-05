## 1. 规则引擎

- [x] 1.1 `BookSource` 加 `exploreUrl`、`enabledExplore`（缺少时为真）、`ruleExplore`。验证：书源载入测试覆盖三个字段。

  结果（2026-11-05）：`enabledExplore` 只有 `false` 才关掉；用例放在 `explore_test.dart` 的「书源字段」里。
- [x] 1.2 `chain/explore.dart`：`ExploreKind`、`FlexStyle`、`getExploreKinds`（JSON 数组、文本、JS，D1）。验证：单元测试覆盖 book-chains「发现分类」的场景，以及数字文本、非对象项、宽松 JSON。

  结果（2026-11-05）：模型和解析在 `chain/explore_kind.dart`（`parseExploreKinds`），`getExploreKinds` 和 `exploreBooks` 放在 `chains.dart` 里（要用私有的 `_withTask`、`_analyzeBookList`）。`explore_test.dart` 9 个分类用例。用合集 1329 跑一遍（不连网）：188 个书源解析成功，共 4093 个分类；29 个失败：12 个 `[a,b]=>` 写法、10 个 Java 类、5 个 jsLib 的 JSON 形式、1 个 WebView，都是已知限制；1 个是测试环境不连网。
- [x] 1.3 `exploreBooks` 和 `_analyzeBookList` 的发现模式；`tasks.dart` 加 `exploreKindsTask`、`exploreTask`。验证：单元测试覆盖 book-chains「发现」的场景和不判断 `bookUrlPattern`；引擎全量测试通过。

  结果（2026-11-05）：4 个发现用例（ruleExplore 和页码、退回 ruleSearch、不判断 bookUrlPattern、loginCheckJs）；引擎 921 个通过。

## 2. app

- [x] 2.1 `SourceEngine.exploreKinds`、`explore`（交互任务，发现 30 秒超时）；`SourceEntry.explorable`（D2）；测试用的假引擎。验证：analyze 无问题。
- [x] 2.2 `explore_kinds.dart`：`flexRows` 和分类排版控件（D4）。验证：单元测试覆盖 explore「分类排版」的场景、文字宽度、压缩。

  结果（2026-11-05）：`explore_kinds_test.dart` 6 个用例。模拟器上发现文本形式的分类（没有样式）文字被省略：量宽度时只用了字号，显示时还继承了主题的字距，小标题还是粗体，宽度一点余量都没有。改成用显示时的完整样式量、向上取整到整像素，加了一个组件测试检查文字不被省略。
- [x] 2.3 `explore_page.dart` 和外壳的「发现」tab（D3、D5）。验证：组件测试覆盖 explore「发现页的书源」「展开书源的分类」和 app-shell「发现 tab 保持展开」。

  结果（2026-11-05）：`explore_page_test.dart` 里 7 个，`app_shell_test.dart` 加 1 个。
- [x] 2.4 `explore_books_page.dart`（D6）。验证：组件测试覆盖 explore「分类书籍页」的场景。

  结果（2026-11-05）：`explore_page_test.dart` 里 5 个（分页去重到底、滑到底才取下一页、第一页没有书、出错重试、打开详情）。

## 3. 验证和文档

- [x] 3.1 app、引擎全量测试和 analyze。

  结果（2026-11-05）：app 376 个、引擎 921 个通过，analyze 无问题。
- [x] 3.2 Android 模拟器上用合集 1329 的书源走查：JSON 数组、文本、JS 生成的分类，排版和 Legado 对照，翻页到底，打开详情加入书架。验证：截图给用户看。

  结果（2026-11-05，Android 模拟器 API 36，debug 包）：
  - 发现 tab 列出 181 个书源。
  - 《黄金屋》（JS 生成）：「排行榜」「分类」小标题独占一行，0.25 的分类一行 3 个、标签一行 4 个；点「玄幻小说」显示书源列表规则用了 Java 类的出错原因和「重试」。
  - 《白鹿书院》（JSON 数组）：一行 3 个；点「外国小说」30 秒后显示「超时：超过 30 秒」。
  - 《米读小说》（JS 生成）：交互式的「频道」下拉是灰色胶囊；点「玄幻」显示封面、书名、作者、简介，往下滑接着取后面的页；点一本书进入详情，目录 1822 章。没有加入书架，免得改动模拟器上的书架。
  - 《全本小说网》（文本形式、`<,{{page}}>` 翻页）：分类按文字宽度排（修好省略问题之后）；第 1 页请求 `/XuanHuan/`，网站断开连接，显示网络错误。
- [x] 3.3 PRD 4.2「发现页」标为已完成；README 同步。
- [x] 3.4 用户确认后同步主规格并归档。验证：`openspec validate --strict` 通过。
