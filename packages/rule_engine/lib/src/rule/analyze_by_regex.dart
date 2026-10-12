import '../core/environment.dart';
import '../core/errors.dart';
import '../regex/source_regex.dart';
import 'content.dart';

/// MD3 的 `AnalyzeByRegex`：AllInOne 正则。
///
/// 规则按 `&&` 分级：前面各级把全部匹配直接拼接，作为下一级的输入；最后一级的每个匹配是一项，
/// 项的内容是全部分组（未参与匹配的组为空串）。正则按 Java 语法编译，编译不了时以规则错误结束。
abstract final class AnalyzeByRegex {
  /// 只取最后一级的第一个匹配。
  static RegexMatchGroups? getElement(RuleEnvironment env, String input, List<String> regs, [int index = 0]) {
    final regex = _compile(regs[index]);
    final first = regex.firstMatch(env, input);
    if (first == null) return null;
    if (index + 1 == regs.length) return _groups(first.groupCount, first.group);
    return getElement(env, _concatMatches(env, regex, input), regs, index + 1);
  }

  static List<RegexMatchGroups> getElements(RuleEnvironment env, String input, List<String> regs, [int index = 0]) {
    final regex = _compile(regs[index]);
    if (regex.firstMatch(env, input) == null) return [];
    if (index + 1 == regs.length) {
      return [for (final match in regex.allMatches(env, input)) _groups(match.groupCount, match.group)];
    }
    return getElements(env, _concatMatches(env, regex, input), regs, index + 1);
  }

  static String _concatMatches(RuleEnvironment env, SourceRegex regex, String input) =>
      regex.allMatches(env, input).map((match) => match.group(0)).join();

  static RegexMatchGroups _groups(int count, String? Function(int) group) =>
      RegexMatchGroups([for (var i = 0; i <= count; i++) group(i) ?? '']);

  static SourceRegex _compile(String pattern) =>
      SourceRegex.tryCompile(pattern) ?? (throw RuleException('正则无法编译：$pattern'));
}
