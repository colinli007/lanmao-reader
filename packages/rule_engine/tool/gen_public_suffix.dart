// 从 publicsuffix.org 的列表生成 lib/src/net/public_suffix_list.dart（MPL-2.0）。
//
//   curl -o public_suffix_list.dat https://publicsuffix.org/list/public_suffix_list.dat
//   dart run tool/gen_public_suffix.dart public_suffix_list.dat
//
// 和 MD3 用的 OkHttp PublicSuffixDatabase 一样，包含 ICANN 和 PRIVATE 两部分。
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('用法：dart run tool/gen_public_suffix.dart <public_suffix_list.dat>');
    exit(64);
  }
  final lines = File(args.single).readAsLinesSync();
  String header(String name) =>
      lines.firstWhere((line) => line.startsWith('// $name:')).substring('// $name:'.length).trim();

  final rules = [
    for (final line in lines)
      if (line.trim().isNotEmpty && !line.startsWith('//')) line.trim().split(RegExp(r'\s')).first,
  ];
  if (rules.any((rule) => rule.contains("'") || rule.contains(r'$') || rule.contains(r'\'))) {
    throw StateError('规则里有需要转义的字符');
  }
  File('lib/src/net/public_suffix_list.dart').writeAsStringSync('''
// 由 tool/gen_public_suffix.dart 生成，不要手改。
// 来源：https://publicsuffix.org/list/public_suffix_list.dat（MPL-2.0，https://mozilla.org/MPL/2.0/）
// VERSION: ${header('VERSION')}
// COMMIT: ${header('COMMIT')}

/// 公共后缀规则，每行一条，含通配符（`*.`）和例外（`!`）规则。
const String publicSuffixRules = \'\'\'
${rules.join('\n')}
\'\'\';
''');
  stdout.writeln('写入 ${rules.length} 条规则');
}
