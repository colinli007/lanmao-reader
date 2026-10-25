import 'dart:convert';

import '../core/environment.dart';
import '../text/lenient_json.dart';
import '../regex/java_replace.dart';
import '../regex/source_regex.dart';
import 'book_source.dart' show SkippedSource;

/// Legado 的替换净化规则（replace-rules「规则的格式」）。[json] 是原始内容，字段按 Legado 的缺省值读取。
final class ReplaceRule {
  /// [json] 里必须有数字 `id`：从 [loadReplaceRules] 得到的规则都已补上。
  const ReplaceRule(this.json);

  final Map<String, Object?> json;

  int get id => (json['id']! as num).toInt();
  String get name => _string('name');
  String get pattern => _string('pattern');
  String get replacement => _string('replacement');
  bool get isRegex => _bool('isRegex', true);
  String get scope => _string('scope');
  String get excludeScope => _string('excludeScope');
  bool get scopeContent => _bool('scopeContent', true);
  bool get scopeTitle => _bool('scopeTitle', false);
  bool get isEnabled => _bool('isEnabled', true);

  /// 一次执行的超时时间；不大于 0 时按 3 秒，同 Legado 的 `getValidTimeoutMillisecond`。
  Duration get timeout => switch (json['timeoutMillisecond']) {
    final num ms when ms > 0 => Duration(milliseconds: ms.toInt()),
    _ => const Duration(seconds: 3),
  };

  /// 执行顺序，小的先执行；缺省是 Legado 的 `Int.MIN_VALUE`。
  int get order => switch (json['order']) {
    final num order => order.toInt(),
    _ => -2147483648,
  };

  String _string(String key) => switch (json[key]) {
    final String value => value,
    _ => '',
  };

  bool _bool(String key, bool fallback) => switch (json[key]) {
    final bool value => value,
    _ => fallback,
  };
}

/// 载入结果：可用的规则和被跳过的条目。
final class ReplaceRuleLoadResult {
  const ReplaceRuleLoadResult(this.rules, this.skipped);

  final List<ReplaceRule> rules;
  final List<SkippedSource> skipped;
}

/// 载入替换规则 JSON：单个规则对象或规则数组。缺 `id` 的规则按当前毫秒时间戳加下标生成。
/// 整个输入不是合法 JSON，或者顶层既不是对象也不是数组时，抛出 [FormatException]。
/// 要编译正则，所以在 worker 里调用（add-replace-rules 设计 D3）。
ReplaceRuleLoadResult loadReplaceRules(String text) {
  final content = text.startsWith('﻿') ? text.substring(1) : text;
  Object? root;
  try {
    root = jsonDecode(content);
  } on FormatException {
    root = parseLenientJson(content);
  }
  final entries = switch (root) {
    List<Object?>() => root,
    Map<String, Object?>() => [root],
    _ => throw FormatException('顶层既不是规则数组也不是单个规则对象'),
  };

  final now = DateTime.now().millisecondsSinceEpoch;
  final rules = <ReplaceRule>[];
  final skipped = <SkippedSource>[];
  for (final (index, entry) in entries.indexed) {
    if (entry is! Map<String, Object?>) {
      skipped.add((index: index, reason: '不是 JSON 对象'));
      continue;
    }
    final rule = ReplaceRule({...entry, if (entry['id'] is! num) 'id': now + index});
    if (replaceRuleError(rule.pattern, isRegex: rule.isRegex) case final reason?) {
      skipped.add((index: index, reason: reason));
    } else {
      rules.add(rule);
    }
  }
  return ReplaceRuleLoadResult(rules, skipped);
}

/// 规则不可用的原因，可用时返回 null。同 Legado 的 `ReplaceRule.isValid`：
/// 替换规则为空；是正则时编译不了，或者末尾是没有转义的 `|`（会匹配空串）。
String? replaceRuleError(String pattern, {required bool isRegex}) {
  if (pattern.isEmpty) return '替换规则为空';
  if (!isRegex) return null;
  if (SourceRegex.tryCompile(pattern) == null) return '正则无法编译';
  if (pattern.endsWith('|') && !pattern.endsWith(r'\|')) return '正则末尾的 | 会匹配空串';
  return null;
}

/// 执行一条正则规则：替换全部匹配，替换串按 Java 语法解释（replace-rules「执行替换」）。
/// 替换串不合法时原样返回。正则编译不了时也原样返回：入库前已经校验过，这里防的是正则转换升级后旧规则编译不了。
String applyReplaceRule(RuleEnvironment env, String input, String pattern, String replacement) {
  final regex = SourceRegex.tryCompile(pattern);
  if (regex == null) return input;
  try {
    return replaceAllJava(env, regex, input, replacement);
  } on FormatException {
    return input;
  }
}
