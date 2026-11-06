/// 一次「书源调试」的结果（md3-diff，add-md3-diff 设计 D2、D4）：两边都转成这个结构再比较。
library;

/// 调试流程的四步。
enum DebugStep {
  search('搜索'),
  info('详情'),
  toc('目录'),
  content('正文');

  const DebugStep(this.label);

  final String label;
}

/// 一步的结果：成功、跳过（MD3 已有目录地址时跳过详情；文件类书源不取目录和正文）或出错，以及取到的字段。
final class StepResult {
  StepResult(this.step);

  final DebugStep step;
  bool ok = false;
  bool skipped = false;
  String? error;

  /// 字段名见 [DebugResult] 的说明。
  final Map<String, String> fields = {};

  bool get passed => ok || skipped;

  Map<String, Object?> toJson() => {
    'ok': ok,
    if (skipped) 'skipped': true,
    if (error != null) 'error': error,
    if (fields.isNotEmpty) 'fields': fields,
  };
}

/// 一边的调试结果。字段：
/// - 搜索：`count`，第一本的 `name`、`author`、`kind`、`wordCount`、`lastChapter`、`intro`、`coverUrl`、`bookUrl`；
/// - 详情：`name`、`author`、`kind`、`wordCount`、`lastChapter`、`intro`、`coverUrl`、`tocUrl`；
/// - 目录：`count`；
/// - 正文：`title`（用的那一章的章节名）、`text`。第一章选得对不对看正文这一步。
final class DebugResult {
  DebugResult();

  final Map<DebugStep, StepResult> steps = {};

  /// 原始日志（MD3 一侧，每条截到 300 个字），写进报告便于排查。
  final List<String> log = [];

  StepResult step(DebugStep step) => steps.putIfAbsent(step, () => StepResult(step));

  /// 从头连续通过的步数（0 到 4）。
  int get progress {
    var count = 0;
    for (final step in DebugStep.values) {
      if (steps[step]?.passed != true) break;
      count++;
    }
    return count;
  }

  bool get completed => progress == DebugStep.values.length;

  /// 没通过的第一步，走完时为 null。
  StepResult? get failure => completed ? null : step(DebugStep.values[progress]);

  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in steps.entries) key.name: value.toJson(),
    if (log.isNotEmpty) 'log': log,
  };

  /// [toJson] 的逆：步骤、字段、日志原样读回。
  factory DebugResult.fromJson(Map<String, Object?> json) {
    final result = DebugResult();
    for (final name in DebugStep.values) {
      if (json[name.name] case final Map<String, Object?> step) {
        result.step(name)
          ..ok = step['ok'] == true
          ..skipped = step['skipped'] == true
          ..error = step['error'] as String?
          ..fields.addAll(((step['fields'] as Map?) ?? const {}).cast<String, String>());
      }
    }
    result.log.addAll(((json['log'] as List?) ?? const []).cast<String>());
    return result;
  }
}

/// 解析 MD3 `/bookSourceDebug` 发回的日志（每条一项，前面是 `[mm:ss.SSS] `）。
///
/// - `︾开始解析X页` 开始一步，`︽X页解析完成` 结束一步；`┌获取X` 之后的一条 `└值` 是字段，值可以有多行；
/// - `◇书籍总数`、`◇目录总数`；
///   目录的「首章信息」不用：它是解析一页时、倒序和去重之前的第一项（去重在倒过来的列表上做，重复的章节留后面那个），
///   不一定是最后用的第一章。正文这一步记的章节名才是；
/// - 出错时是 `︽未获取到书籍`、`≡没有正文章节`（算正文这一步）或异常的堆栈（取第一行）；
/// - 日志结束时还没结束的一步记为「没有结束」（超时、连接断开）。
///
/// 详情的日志是每条规则取到的值，不是书最后的值：MD3 的 `BookInfo` 只在取到的值不为空时赋值，书名和作者还要求
/// [canReName]（书源有 `ruleBookInfo.canReName`）或者搜索时没取到。解析完按这个规则用搜索的字段补齐，
/// 详情的字段就是 MD3 执行完详情后书的值，和我们一侧（书的最终值）可以直接比较。
///
/// 搜索记的是列表第 0 项的字段：它的书名为空时这一项被丢掉了，详情用的是后面一本，这时搜索的第一本字段不比较，
/// 详情也只留一定会赋值的字段。
DebugResult parseMd3Log(List<String> messages, {bool canReName = false}) {
  final result = DebugResult();
  StepResult? current;
  String? pendingField;
  for (final raw in messages) {
    final message = raw.replaceFirst(_timePrefix, '');
    if (message.startsWith('︾开始解析')) {
      current = switch (message) {
        '︾开始解析搜索页' => result.step(DebugStep.search),
        '︾开始解析详情页' => result.step(DebugStep.info),
        '︾开始解析目录页' => result.step(DebugStep.toc),
        '︾开始解析正文页' => result.step(DebugStep.content),
        _ => current,
      };
      pendingField = null;
    } else if (current == null) {
      continue;
    } else if (message.startsWith('︽') && message.endsWith('解析完成')) {
      current.ok = true;
    } else if (message == '︽未获取到书籍') {
      current.error = '未获取到书籍';
    } else if (message == '≡没有正文章节') {
      // 目录已经解析完成，取不到第一章算正文这一步失败
      result.step(DebugStep.content).error = '没有正文章节';
    } else if (message.startsWith('≡已获取目录链接')) {
      result.step(DebugStep.info).skipped = true;
    } else if (message.startsWith('≡文件类书源跳过解析目录')) {
      result.step(DebugStep.toc).skipped = true;
      result.step(DebugStep.content).skipped = true;
    } else if (message.startsWith('┌获取')) {
      pendingField = _fieldNames[current.step]?[message.substring(3)];
    } else if (message.startsWith('└')) {
      final field = pendingField;
      if (field != null) current.fields.putIfAbsent(field, () => message.substring(1));
      pendingField = null;
    } else if (message.startsWith('◇')) {
      final colon = message.indexOf(':');
      final name = colon < 0 ? null : _countNames[message.substring(1, colon)];
      if (name != null) current.fields.putIfAbsent(name, () => message.substring(colon + 1));
    } else if (_exception.hasMatch(message) && current.error == null && !current.ok) {
      current.error = message.split('\n').first.trim();
    }
  }
  for (final step in result.steps.values) {
    if (!step.passed && step.error == null) step.error = '没有结束';
  }
  final search = result.steps[DebugStep.search];
  final dropped = search != null && (search.fields['name']?.trim().isEmpty ?? false);
  if (dropped) search.fields.removeWhere((field, _) => field != 'count');
  _settleInfo(result, canReName: canReName, searchKnown: !dropped);
  return result;
}

void _settleInfo(DebugResult result, {required bool canReName, required bool searchKnown}) {
  final info = result.steps[DebugStep.info];
  if (info == null || !info.ok) return;
  final search = result.steps[DebugStep.search]?.fields ?? const {};
  for (final field in const ['name', 'author', 'kind', 'wordCount', 'lastChapter', 'intro', 'coverUrl']) {
    final logged = info.fields[field] ?? '';
    final isTitle = field == 'name' || field == 'author';
    if (!searchKnown) {
      // 不知道搜索时那一本的值：只有一定会赋值的字段知道最后的值
      if (logged.isEmpty || (isTitle && !canReName)) info.fields.remove(field);
      continue;
    }
    final before = search[field] ?? '';
    final rename = !isTitle || canReName || before.isEmpty;
    info.fields[field] = logged.isNotEmpty && rename ? logged : before;
  }
}

final RegExp _timePrefix = RegExp(r'^\[\d+:\d+\.\d+\] ?');

/// 异常堆栈的第一行：`包名.类名: 消息` 或 `类名: 消息`，类名以 Exception、Error 结尾。
final RegExp _exception = RegExp(r'^[\w.$]*(Exception|Error)\b');

const Map<DebugStep, Map<String, String>> _fieldNames = {
  DebugStep.search: {
    '书名': 'name',
    '作者': 'author',
    '分类': 'kind',
    '字数': 'wordCount',
    '最新章节': 'lastChapter',
    '简介': 'intro',
    '封面链接': 'coverUrl',
    '详情页链接': 'bookUrl',
  },
  DebugStep.info: {
    '书名': 'name',
    '作者': 'author',
    '分类': 'kind',
    '字数': 'wordCount',
    '最新章节': 'lastChapter',
    '简介': 'intro',
    '封面链接': 'coverUrl',
    '目录链接': 'tocUrl',
  },
  DebugStep.content: {'章节名称': 'title', '正文内容': 'text'},
};

const Map<String, String> _countNames = {'书籍总数': 'count', '目录总数': 'count'};
