// 从 WHATWG Encoding Standard 的 index-gb18030.txt 生成 GBK 双字节码表 lib/src/text/gbk_table.dart。
//
//   curl -o index-gb18030.txt https://encoding.spec.whatwg.org/index-gb18030.txt
//   dart run tool/gen_gbk.dart index-gb18030.txt
//
// 码表只生成一次；换版本时重跑，并核对生成文件头部记录的来源标识。
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('用法：dart run tool/gen_gbk.dart <index-gb18030.txt>');
    exit(64);
  }
  final lines = File(args.single).readAsLinesSync();
  final identifier = _header(lines, 'Identifier');
  final date = _header(lines, 'Date');

  // 双字节部分共 126 个首字节 × 190 个尾字节
  const size = 126 * 190;
  final table = List<int?>.filled(size, null);
  for (final line in lines) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final fields = line.trim().split(RegExp(r'\s+'));
    final pointer = int.parse(fields[0]);
    final codePoint = int.parse(fields[1].substring(2), radix: 16);
    if (codePoint > 0xFFFF) throw StateError('双字节部分不应有 BMP 以外的字符：$line');
    table[pointer] = codePoint;
  }
  final missing = table.indexOf(null);
  if (missing >= 0) throw StateError('指针 $missing 没有对应的字符');

  final literal = StringBuffer();
  for (final codePoint in table.cast<int>()) {
    literal.write(_escape(codePoint));
  }
  File('lib/src/text/gbk_table.dart').writeAsStringSync('''
// 由 tool/gen_gbk.dart 生成，不要手改。
// 来源：https://encoding.spec.whatwg.org/index-gb18030.txt
// Identifier: $identifier
// Date: $date

/// GBK 双字节码表：第 pointer 个字符是指针 pointer 对应的字符，
/// pointer = (首字节 - 0x81) × 190 + (尾字节 - (尾字节 < 0x7F ? 0x40 : 0x41))。
const String gbkTable = '$literal';
''');
  stdout.writeln('写入 $size 项');
}

String _header(List<String> lines, String name) =>
    lines.firstWhere((line) => line.startsWith('# $name:')).substring('# $name:'.length).trim();

// 可见字符原样写入，控制字符、私用区和字符串字面量里的特殊字符转义
String _escape(int codePoint) {
  final isSpecial = codePoint < 0x20 ||
      (codePoint >= 0x7F && codePoint <= 0x9F) ||
      (codePoint >= 0xE000 && codePoint <= 0xF8FF) ||
      codePoint == 0x27 ||
      codePoint == 0x24 ||
      codePoint == 0x5C;
  return isSpecial ? '\\u${codePoint.toRadixString(16).padLeft(4, '0')}' : String.fromCharCode(codePoint);
}
