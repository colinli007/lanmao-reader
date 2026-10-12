import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

import '../core/environment.dart';
import 'source_regex.dart';

/// 规则里的 `##正则##替换` 净化，照 MD3 的 `AnalyzeRule.replaceRegex`：
/// - 默认替换全部匹配；正则编译不了或替换串不合法时，退化为字面量替换；
/// - [firstOnly]（写成 `##正则##替换###`）时只取第一个匹配，结果是这段匹配按正则替换后的文本，没有匹配时为空；
///   正则编译不了或替换串不合法时，结果是替换串本身。
String replaceByRule(
  RuleEnvironment env,
  String input,
  String pattern,
  String replacement, {
  required bool firstOnly,
}) {
  if (pattern.isEmpty) return input;
  final regex = SourceRegex.tryCompile(pattern);
  if (firstOnly) {
    if (regex != null) {
      try {
        final match = regex.firstMatch(env, input);
        return match == null ? '' : replaceFirstJava(env, regex, match.group(0)!, replacement);
      } on FormatException {
        // 退化，同下
      }
    }
    return replacement;
  }
  if (regex != null) {
    try {
      return replaceAllJava(env, regex, input, replacement);
    } on FormatException {
      // 退化为字面量替换
    }
  }
  return input.replaceAll(pattern, replacement);
}

/// Kotlin 的 `input.replace(regex, replacement)`，即 Java `Matcher.replaceAll`：替换串按 Java 语法解释。
/// 没有匹配时原样返回；有匹配而替换串不合法时抛出 [FormatException]（Java 在这时才报错）。
String replaceAllJava(RuleEnvironment env, SourceRegex regex, String input, String replacement) {
  final matches = regex.allMatches(env, input);
  if (matches.isEmpty) return input;
  final template = _JavaReplacement.parse(replacement, regex);
  final out = StringBuffer();
  var last = 0;
  for (final match in matches) {
    out
      ..write(input.substring(last, match.start))
      ..write(template.expand(match));
    last = match.end;
  }
  out.write(input.substring(last));
  return out.toString();
}

/// Kotlin 的 `input.replaceFirst(regex, replacement)`，即 Java `Matcher.replaceFirst`。
String replaceFirstJava(RuleEnvironment env, SourceRegex regex, String input, String replacement) {
  final match = regex.firstMatch(env, input);
  if (match == null) return input;
  final expanded = _JavaReplacement.parse(replacement, regex).expand(match);
  return input.substring(0, match.start) + expanded + input.substring(match.end);
}

/// 解析后的替换串：字面量和分组引用交替。照 Java `Matcher.appendExpandedReplacement` 的规则：
/// `\x` 是字面量 x；`$n` 尽量多取数字，但不超过分组数；`${name}` 引用命名分组；未参与匹配的组替换为空。
final class _JavaReplacement {
  _JavaReplacement._(this._parts);

  factory _JavaReplacement.parse(String replacement, SourceRegex regex) {
    final parts = <Object>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isEmpty) return;
      parts.add(literal.toString());
      literal.clear();
    }

    var i = 0;
    while (i < replacement.length) {
      final char = replacement[i++];
      if (char == r'\') {
        if (i >= replacement.length) throw FormatException('替换串末尾缺少被转义的字符', replacement);
        literal.write(replacement[i++]);
        continue;
      }
      if (char != r'$') {
        literal.write(char);
        continue;
      }
      if (i >= replacement.length) throw FormatException('替换串里的 \$ 后面缺少分组', replacement);
      int group;
      if (replacement[i] == '{') {
        final end = replacement.indexOf('}', i);
        final name = end < 0 ? '' : replacement.substring(i + 1, end);
        if (!_groupName.hasMatch(name)) throw FormatException('不合法的命名分组引用', replacement, i);
        group = regex.groupIndex(name) ?? (throw FormatException('没有命名分组 $name', replacement, i));
        i = end + 1;
      } else {
        group = _digit(replacement, i) ?? (throw FormatException('不合法的分组引用', replacement, i));
        i++;
        while (i < replacement.length) {
          final digit = _digit(replacement, i);
          if (digit == null || group * 10 + digit > regex.groupCount) break;
          group = group * 10 + digit;
          i++;
        }
        if (group > regex.groupCount) throw FormatException('没有第 $group 组', replacement, i);
      }
      flush();
      parts.add(group);
    }
    flush();
    return _JavaReplacement._(parts);
  }

  /// 字面量（[String]）或分组序号（[int]）。
  final List<Object> _parts;

  String expand(JsRegExpMatch match) {
    final out = StringBuffer();
    for (final part in _parts) {
      out.write(part is int ? match.group(part) ?? '' : part);
    }
    return out.toString();
  }

  static int? _digit(String text, int index) {
    final unit = text.codeUnitAt(index) - 0x30;
    return unit >= 0 && unit <= 9 ? unit : null;
  }

  /// Java 只认 ASCII 字母和数字组成、不以数字开头的组名。
  static final RegExp _groupName = RegExp(r'^[A-Za-z][A-Za-z0-9]*$');
}
