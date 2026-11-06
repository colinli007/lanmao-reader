/// 两边调试结果的对比、分类和报告（md3-diff「对比和分类」「报告」，add-md3-diff 设计 D4、D5）。
library;

import 'debug_result.dart';

/// 一个书源的分类。
enum DiffCategory {
  same('一致'),
  oursFailed('只有我们失败'),
  md3Failed('只有 MD3 失败'),
  bothFailed('都失败'),
  fieldsDiffer('字段不同');

  const DiffCategory(this.label);

  final String label;
}

/// 一个字段的不同：[note] 是正文不同时的长度和第一处不同的位置。
typedef FieldDiff = ({DebugStep step, String field, String ours, String md3, String? note});

final class SourceDiff {
  SourceDiff({required this.name, required this.url, required this.key, required this.ours, required this.md3})
    : diffs = _fieldDiffs(ours, md3) {
    category = switch (ours.progress.compareTo(md3.progress)) {
      < 0 => DiffCategory.oursFailed,
      > 0 => DiffCategory.md3Failed,
      _ when diffs.isNotEmpty => DiffCategory.fieldsDiffer,
      _ when !ours.completed => DiffCategory.bothFailed,
      _ => DiffCategory.same,
    };
  }

  final String name;
  final String url;
  final String key;
  final DebugResult ours;
  final DebugResult md3;
  final List<FieldDiff> diffs;
  late final DiffCategory category;

  /// 从报告里读回（`--resume`）：两边的结果原样读回，分类和不同的字段重新算。
  factory SourceDiff.fromJson(Map<String, Object?> json) => SourceDiff(
    name: json['name']! as String,
    url: json['url']! as String,
    key: json['key']! as String,
    ours: DebugResult.fromJson(json['ours']! as Map<String, Object?>),
    md3: DebugResult.fromJson(json['md3']! as Map<String, Object?>),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'key': key,
    'category': category.label,
    if (diffs.isNotEmpty)
      'diffs': [
        for (final d in diffs)
          {'step': d.step.label, 'field': d.field, 'ours': _clip(d.ours, 300), 'md3': _clip(d.md3, 300), 'note': ?d.note},
      ],
    'ours': ours.toJson(),
    'md3': md3.toJson(),
  };
}

/// 显示用：去掉首尾空白，连续空白合并成一个空格。
String normalizeText(String text) => text.trim().replaceAll(_spaces, ' ');

/// 比较用：去掉全部空白（含全角空格）。中文里换行、缩进的差别不算内容不同。
String _compact(String text) => text.replaceAll(_spaces, '');

final RegExp _spaces = RegExp(r'\s+');

/// 两边都通过（不是跳过）的步骤里，MD3 记下的每个字段和我们的比较。
List<FieldDiff> _fieldDiffs(DebugResult ours, DebugResult md3) => [
  for (final step in DebugStep.values)
    if (ours.steps[step] case final a? when a.ok && !a.skipped)
      if (md3.steps[step] case final b? when b.ok && !b.skipped)
        for (final MapEntry(key: field, value: theirs) in b.fields.entries)
          if (_differ(field, a.fields[field] ?? '', theirs) case final note?) (
            step: step,
            field: field,
            ours: a.fields[field] ?? '',
            md3: theirs,
            note: note.isEmpty ? null : note,
          ),
];

/// 不同时返回说明（短文本为空串），相同时为 null。正文说明两边的长度和第一处不同的位置及前后各 20 个字。
/// MD3 日志里的封面是规则取到的原始值（赋值时才转成绝对地址），是相对地址时我们的以它结尾就算相同。
String? _differ(String field, String ours, String md3) {
  final a = _compact(ours);
  final b = _compact(md3);
  if (a == b) return null;
  if (field == 'coverUrl' && b.isNotEmpty && !b.startsWith('http') && a.endsWith(b)) return null;
  if (_urlFields.contains(field) && _maskVolatile(a) == _maskVolatile(b)) return null;
  if (a.length < 80 && b.length < 80) return '';
  var at = 0;
  while (at < a.length && at < b.length && a[at] == b[at]) {
    at++;
  }
  String around(String s) => s.substring((at - 20).clamp(0, s.length), (at + 20).clamp(0, s.length));
  return '长度 ${a.length} / ${b.length}，第 $at 个字起不同：「${around(a)}」/「${around(b)}」';
}

const Set<String> _urlFields = {'bookUrl', 'tocUrl', 'coverUrl'};

/// 地址里每次请求都会变的查询参数值（时间戳、签名、随机编号）：8 个以上的字母数字，两边长度相同时视为相同。
/// 含 `%` 等的值照常比较，编码问题不会被盖住。
String _maskVolatile(String url) {
  final query = url.indexOf('?');
  if (query < 0) return url;
  return url.substring(0, query) +
      url.substring(query).replaceAllMapped(RegExp(r'=([A-Za-z0-9_-]{8,})(?=&|$)'), (m) => '=<${m[1]!.length}>');
}

String _clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max)}…';

/// 错误消息归类：去掉末尾括号里的书源名和字段、地址和数字，便于同类合并。
String errorCategory(String error) => error
    .split('\n')
    .first
    .replaceAll(RegExp(r'（[^（）]*）$'), '')
    .replaceAll(RegExp(r'https?://\S+'), '<地址>')
    .replaceAll(RegExp(r'\d+'), 'N')
    .trim();

/// Markdown 摘要：各类数量；只有我们失败、只有 MD3 失败按原因归类；字段不同按字段计数并举例。
String markdownSummary(List<SourceDiff> diffs, {required String md3Version, required DateTime date}) {
  final out = StringBuffer()
    ..writeln('# 和 MD3 的差分测试')
    ..writeln()
    ..writeln('${date.toIso8601String().substring(0, 16)}，MD3 $md3Version，${diffs.length} 个书源，关键词按书源校验的规则（默认「我的」）。')
    ..writeln()
    ..writeln('| 分类 | 书源数 |')
    ..writeln('|---|---|');
  for (final category in DiffCategory.values) {
    out.writeln('| ${category.label} | ${diffs.where((d) => d.category == category).length} |');
  }

  void grouped(String title, DiffCategory category, StepResult? Function(SourceDiff) failure) {
    final groups = <String, List<SourceDiff>>{};
    for (final diff in diffs.where((d) => d.category == category)) {
      final step = failure(diff);
      final key = '${step?.step.label ?? ''}｜${errorCategory(step?.error ?? '')}';
      (groups[key] ??= []).add(diff);
    }
    if (groups.isEmpty) return;
    out
      ..writeln()
      ..writeln('## $title')
      ..writeln();
    for (final entry in groups.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))) {
      out.writeln('- ${entry.value.length} 个｜${entry.key}：${entry.value.map((d) => d.name).take(8).join('、')}'
          '${entry.value.length > 8 ? ' 等' : ''}');
    }
  }

  grouped('只有我们失败（按我们出错的步骤和原因）', DiffCategory.oursFailed, (d) => d.ours.failure);
  grouped('只有 MD3 失败（按 MD3 出错的步骤和原因）', DiffCategory.md3Failed, (d) => d.md3.failure);
  grouped('都失败（按步骤和 MD3 的原因）', DiffCategory.bothFailed, (d) => d.md3.failure);

  final fields = <String, List<(SourceDiff, FieldDiff)>>{};
  for (final diff in diffs) {
    for (final field in diff.diffs) {
      (fields['${field.step.label}.${field.field}'] ??= []).add((diff, field));
    }
  }
  if (fields.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## 字段不同（含其它分类里的书源）')
      ..writeln();
    for (final entry in fields.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))) {
      out.writeln('- ${entry.key}：${entry.value.length} 个');
      for (final (diff, field) in entry.value.take(3)) {
        out.writeln('  - ${diff.name}：我们「${_clip(normalizeText(field.ours), 60)}」，MD3「${_clip(normalizeText(field.md3), 60)}」'
            '${field.note == null ? '' : '（${field.note}）'}');
      }
    }
  }
  return out.toString();
}
