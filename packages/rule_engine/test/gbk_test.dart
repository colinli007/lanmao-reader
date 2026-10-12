import 'package:rule_engine/src/text/gbk.dart';
import 'package:test/test.dart';

void main() {
  test('三体 ↔ C8 FD CC E5', () {
    expect(gbk.encode('三体'), [0xC8, 0xFD, 0xCC, 0xE5]);
    expect(gbk.decode([0xC8, 0xFD, 0xCC, 0xE5]), '三体');
  });

  test('GB2312 常用字和 ASCII 混排往返', () {
    const text = '第1章 天下第一，“你好”！ABC';
    expect(gbk.decode(gbk.encode(text)), text);
    // 「啊」是 GB2312 第一个汉字，「齄」是最后一个
    expect(gbk.encode('啊齄'), [0xB0, 0xA1, 0xF7, 0xFE]);
  });

  test('GBK 扩展区（GB2312 以外）', () {
    expect(gbk.decode([0x81, 0x40]), '丂');
    // 「镕」「堃」不在 GB2312 里
    expect(gbk.decode(gbk.encode('镕堃')), '镕堃');
  });

  test('非法字节替换为 U+FFFD', () {
    expect(gbk.decode([0xFF]), '�');
    expect(gbk.decode([0x41, 0xC8]), 'A�');
    // 尾字节不合法但是 ASCII 时，首字节算一个错误，ASCII 照常输出
    expect(gbk.decode([0xC8, 0x30]), '�0');
    expect(gbk.decode([0x80]), '€');
  });

  test('GBK 里没有的字符编码为 ?', () {
    expect(gbk.encode('a😀b'), [0x61, 0x3F, 0x62]);
  });
}
