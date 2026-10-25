## Context

动机和范围见 proposal.md。行为要求见四份 delta spec：

- `specs/replace-rules/spec.md`：新能力，规则的格式、管理和执行。
- `specs/reader/spec.md`：「替换净化」。
- `specs/settings/spec.md`：「设置页入口」。
- `specs/app-storage/spec.md`：「落盘的数据」「清除正文缓存」。

### 现状

- **正则**：rule_engine 里已经有一套 Java 正则的实现，书源规则的 `##正则##替换` 就用它：
  - `SourceRegex` 把 Java 语法转成 JS 语法，在 quickjs 的 libregexp 里执行，匹配过程会检查任务的中止信号。rule-syntax「书源正则可以被中止」有测试：`(a+)+b` 被取消后，worker 能在宽限期内结束，不用放弃。
  - `replaceAllJava` 按 Java 语法解释替换串（`$1`、`${name}`、`\` 转义），替换串不合法时抛 `FormatException`。
  - 编译结果缓存在每个 isolate 里，每个 isolate 一个 `JsEngine`。现在只有 worker 里会用到，主 isolate 没有创建过。
- **worker 池**：`WorkerPool.run(task, timeout:)` 的超时从任务开始执行时算，不含排队。超时后提交方收到 `TaskTimeoutException`，worker 里正在跑的正则被中止。
- **正文**：
  - 阅读页的 `_text` 先读 `contents` 缓存，没有时调用 `BookContentSource.loadContent`，并把结果写入缓存。
  - `_formatted` 再调用 `formatChapter` 分段。
  - 缓存里存的是书源链路的输出：书源自己的 `replaceRegex` 已经执行过，这是书源的一部分。
- **模块边界**：
  - `lib/online/` 以外不能引用 `rule_engine`，`module_boundary_test` 会检查。
  - 阅读页只认 `library/` 的 `BookContentSource`，由 `OnlineContentSource` 实现。
- **书源的导入和管理**：
  - `source_list_page.dart` 里有取导入文本的写法：从文件、网址、粘贴文本三种方式拿到文本，`_InputDialog`、`_pickFile` 都是私有的。
  - `source_import.dart` 里有 `previewImport`、`downloadSourceText`、`ImportException`。
  - `SourceRepository` 启动时从数据库载入、解析一次。每次改动先写数据库，再整体重新载入，然后 `notifyListeners`。
- **数据库**：`schemaVersion` 是 1，还没有迁移代码。开发用的模拟器上已经有 v1 的数据库。

## Goals / Non-Goals

**Goals:**

- 正则的语法和结果跟 Legado 一致，而且一条坏正则卡不住阅读页。
- 规则只作用在显示上，缓存里一直是原文。
- 导入、取文本、仓库的写法和书源保持一致，不再写第二套。

**Non-Goals:**

- 替换的性能优化，比如把多条规则合并成一个任务、缓存替换后的结果。先测量，见 Risks。
- 阅读页打开期间修改规则后实时重排：入口只在设置页，设置页和阅读页不会同时在导航栈里。

## Decisions

### D1 在显示前替换，不在写缓存前替换

替换净化本质上是对书源输出的一层显示加工，规则会被用户改动。所以：

- 缓存保存原文。
- 每次排版前，用当时的规则执行一遍。

**否决的方案**：在 `loadContent` 之后、写缓存之前替换。这样每改一次规则就要清缓存、重新联网，和 reader「替换净化」场景「改规则后不用清缓存」矛盾。

Legado 也是这样做的：`ContentProcessor` 在显示时替换。

替换发生在 `formatChapter` 之前、作用于整章文字：

- 正文去掉重复章节名，用的是替换后的第一行和替换后的章节名。
- 规则可以跨行匹配：正则开了 `(?s)` 时，`.` 能匹配换行。这和 Legado 对整章做 `replace` 一致。

### D2 正则在 worker 里执行，一条规则一个任务

每条正则规则对一章执行一次，用 `WorkerPool.run(replaceTask(...), timeout: 规则的超时时间)`。

**为什么不在主 isolate 用 Dart `RegExp`**：

- Dart 的 `RegExp` 是 JS 语法，不认 Java 写法：`(?i)` 开头标志、占有量词、`\h`，以及 ICU 的 `\d`、`\w`。
- Dart 的 `RegExp` 不能中途打断，灾难性回溯会卡死界面。

rule_engine 已经解决了这两个问题，也就是 `SourceRegex` 和 `replaceAllJava`，所以直接复用。

**为什么一条规则一个任务，而不是一章一个任务**：

- 超时要落到具体哪一条规则上，才能停用这一条。超时和停用见 D5。
- 一章一个任务时，超时只知道「这一章超时了」，不知道是哪条。要知道就得让 worker 中途上报进度，复杂得多。

一条规则一个任务的代价是每条规则一次 isolate 往返，要复制整章文字（通常 5 到 20 KB）。估计每次往返在 1 毫秒以内，100 条规则在 100 毫秒以内。实现时实测，见 Risks。

**普通文本规则在主 isolate 直接 `replaceAll`**：普通文本替换是线性的，不会卡住，不值得一次往返。

rule_engine 新增的内容：

- `ReplaceRule`：解析后的规则，持有原始 JSON 和带缺省值的字段。
- `loadReplaceRules(text)`：解析 Legado 替换规则 JSON，返回规则和跳过的项。写法照 `loadBookSources`。
- `replaceRuleError(pattern, isRegex)`：返回规则不可用的原因，可用时返回 null。不可用的情况：
  - 正则编译不了。
  - 末尾是没有转义的 `|`。
- `applyReplaceRule(env, input, pattern, replacement)`：执行一条正则规则。
  - 用 `SourceRegex.tryCompile` 和 `replaceAllJava`。
  - 替换串不合法（`FormatException`）时返回原文。
  - 编译不了时也返回原文。这条规则在导入和保存时就会被拦下，这里只是兜底：用户编辑数据库或者升级了正则转换都可能让它出现。
- worker 任务工厂：`replaceTask`、`loadReplaceRulesTask`、`replaceRuleErrorTask`。

### D3 解析和校验也放在 worker 里

导入预览和编辑页保存都要判断正则能不能编译，编译需要当前 isolate 里有一个 `JsEngine`。

`SourceRegex` 的 `JsEngine` 是按 isolate 懒创建的，主 isolate 现在没有。所以导入预览（`loadReplaceRulesTask`）和保存前的校验（`replaceRuleErrorTask`）都交给 worker 池，主 isolate 保持不加载 quickjs。

这两个操作本来就是异步的：导入要等文件或网络，保存要等写库。多一次 worker 往返，用户感觉不到。

**否决的方案**：在主 isolate 建一个 `JsEngine` 只用来编译。这能省一次往返，但会多占一份 quickjs 运行时，还会打破「quickjs 只在 worker 里」的现状。

启动时从数据库载入规则不做正则校验：入库前已经校验过，只解析 JSON。

### D4 存储：一张表，存原始 JSON

新表 `replace_rules`：

| 列 | 说明 |
|---|---|
| `id` | 整数，主键，Legado 的规则 id |
| `json` | 原始 JSON，编辑后的字段写回这里 |
| `enabled` | 启用状态 |

这和 `sources` 表一样，只存原始 JSON 和启用状态：

- 未知字段原样保留，导出时带出。
- 加字段不用改表。

`isEnabled` 单独成列，因为开关是最常改的，改它不需要重写 JSON。导出时用列的值覆盖 JSON 里的 `isEnabled`，和书源导出覆盖 `enabled` 一样。

**排序**不存单独的列：载入后在内存里按 (`order`, `id`) 排。规则的条数是几十到几百，排序可以忽略。新建规则时：

- `order` 取现有最大值加 1。
- `id` 取当前毫秒时间戳，和 Legado 一样；和已有 id 冲突时取最大 id 加 1。

**迁移**：

- `schemaVersion` 改为 2。
- 加 `MigrationStrategy`：`onCreate` 建全部表，`onUpgrade` 在 `from < 2` 时 `createTable(replaceRules)`。
- 以前的表不动。

### D5 超时：中止、跳过、停用，只提示一次

`replaceTask` 抛出 `TaskTimeoutException` 时：

- 这一章跳过这条规则，用执行它之前的文字继续执行后面的规则。
- 仓库停用这条规则并落盘。

这和 Legado 一致：Legado 遇到 `RegexTimeoutException` 也是把规则停用。区别是 Legado 把这一章的正文换成了错误信息，这里改成跳过，让这一章照常可读。

预加载会让相邻的几章同时执行同一条规则。为了不对同一条规则提示好几次，也不让每章都再卡一次：

- 执行每条正则规则之前，从仓库读它当前是否还启用，不用这一章开始时的快照。
- 仓库的停用操作返回「这次是否真的从启用变成了停用」，只有返回真的那次放进提示列表。

阅读页收到停用的规则名后，弹出 SnackBar「替换规则「名称」超时，已停用」。

其它错误统一按「这条规则不改变文字」处理，比如 worker 异常退出。替换出错 MUST NOT 让章节加载失败。

### D6 接口：`BookContentSource.purify`

`library/content_source.dart` 的 `BookContentSource` 新增：

```dart
/// 按替换净化规则处理一章的章节名和正文（reader「替换净化」）。不抛出错误。
Future<Purified> purify(ShelfBook book, ChapterText text);

/// 处理后的章节，以及这次因为超时被停用的规则名。
typedef Purified = ({ChapterText text, List<String> disabled});
```

`OnlineContentSource` 实现它：

1. 从仓库取出对这本书生效的规则：启用，作用范围和排除范围按书名和 `origin` 判断。
2. 依次执行。
3. 正则规则交给 `SourceEngine.replace`。

`SourceEngine` 新增三个方法：`replace`、`loadReplaceRules`、`replaceRuleError`。`PoolSourceEngine` 用 D2 的任务实现它们，测试里的 `FakeEngine` 直接在当前 isolate 调用。

**为什么放在 `BookContentSource` 上**：阅读页不能引用 `rule_engine`，净化又离不开 worker 池和规则仓库，这两样都在 `online/`。`BookContentSource` 本来就是「阅读器取正文」的接口，净化是取正文的最后一步，放在这里最合适。以后做不带书源的版本时，这个实现可以直接原样返回。

### D7 规则仓库和页面

**`ReplaceRuleRepository`**（`online/replace_rule_repository.dart`），写法照 `SourceRepository`：

- 是一个 `ChangeNotifier`，启动时 `load(db)`。
- 每次改动先写数据库，再重新载入，然后通知监听者。
- 提供的操作：`import`、`save`（新建或编辑）、`setEnabled`、`disable`（返回是否改变了状态）、`delete`、`export`。
- 在 `startServices` 里创建，通过 provider 注入，传给 `OnlineContentSource`。

**页面**：

- `replace_rule_list_page.dart`：列表、启用开关、导入菜单、新建、导出。
- `replace_rule_edit_page.dart`：表单，保存前用 `replaceRuleError` 校验，删除前确认。

**导入取文本的写法共用**：把 `source_list_page.dart` 里这几样搬到 `online/import_text.dart`，书源列表和规则列表都用它：

- 三种来源的菜单项
- `_pickFile`
- `_askInput` 和 `_InputDialog`
- `downloadSourceText`：改名 `downloadText`，因为它本来就不关心内容是什么。

`ImportException` 也搬过去。书源导入的行为不变。

## Risks / Trade-offs

- **[规则多时打开章节变慢]** 一条正则规则一次 isolate 往返；每章执行一次，预加载的相邻章也一样。
  - 缓解：实现时在 Android 模拟器上测一章 10 KB、100 条正则规则的耗时，结果记进 tasks。
  - 如果超过 100 毫秒，再改成一章一个任务、按规则分段上报。这只影响 `OnlineContentSource.purify` 的内部，规格和接口都不用变。
- **[Java 正则和 libregexp 的差异]** 少数 Java 写法转不过去，比如字符类里的 `\D`、`\W`，以及后向断言里的变长写法。这些规则会在导入时被标为「正则无法编译」而跳过，或者匹配结果和 Legado 不同。
  - 这和书源净化正则的现状一样。以后修 `translateJavaRegex`，两边一起受益。
- **[超时后正则还在 worker 里跑]** 中止信号要等 libregexp 的下一次检查才生效。rule-syntax 的测试表明，这个时间在宽限期以内。超过宽限期时，池会放弃那个 worker 并补一个新的。阅读页不会因此卡住。
- **[自动停用让用户困惑]** 规则被停用后，广告会重新出现。
  - 缓解：提示里写明是哪条规则、为什么停用。用户可以在列表里重新启用，或者改写这条正则。

## Migration Plan

- 开发机和模拟器上已有的 v1 数据库，启动时自动升到 v2，只新增一张空表。
- 第一版还没发布，没有线上用户。迁移代码和测试保留下来，作为以后改表时的写法。
- 回滚：退回旧版本的 app 时，drift 遇到更高的 `user_version` 会报错。开发期间删掉 app 数据即可，不提供降级迁移。
