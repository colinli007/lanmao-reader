import 'dart:convert';
import 'dart:typed_data';

import 'gbk_table.dart';

/// GBK 编解码（兼容 GB2312），按 WHATWG Encoding Standard 的 gbk 编码实现，只含单字节和双字节部分。
///
/// 解码时无法识别的字节替换为 U+FFFD；编码时 GBK 里没有的字符替换为 `?`，和 Java 的 `getBytes("GBK")` 一致。
const GbkCodec gbk = GbkCodec();

final class GbkCodec extends Encoding {
  const GbkCodec();

  @override
  String get name => 'gbk';

  @override
  Converter<List<int>, String> get decoder => const GbkDecoder();

  @override
  Converter<String, List<int>> get encoder => const GbkEncoder();
}

final class GbkDecoder extends Converter<List<int>, String> {
  const GbkDecoder();

  @override
  String convert(List<int> input) {
    final out = StringBuffer();
    var i = 0;
    while (i < input.length) {
      final byte = input[i++];
      if (byte < 0x80) {
        out.writeCharCode(byte);
      } else if (byte == 0x80) {
        out.writeCharCode(0x20AC);
      } else if (byte == 0xFF || i >= input.length) {
        out.writeCharCode(0xFFFD);
      } else {
        final trail = input[i];
        final offset = trail < 0x7F ? 0x40 : 0x41;
        if ((trail >= 0x40 && trail <= 0x7E) || (trail >= 0x80 && trail <= 0xFE)) {
          out.write(gbkTable[(byte - 0x81) * 190 + trail - offset]);
          i++;
        } else {
          // 尾字节不合法：首字节算一个错误，ASCII 的尾字节留给下一轮重新处理
          out.writeCharCode(0xFFFD);
          if (trail >= 0x80) i++;
        }
      }
    }
    return out.toString();
  }
}

final class GbkEncoder extends Converter<String, List<int>> {
  const GbkEncoder();

  /// 字符到指针，取码表里第一次出现的位置。
  static final Map<int, int> _pointers = () {
    final pointers = <int, int>{};
    for (var pointer = 0; pointer < gbkTable.length; pointer++) {
      pointers.putIfAbsent(gbkTable.codeUnitAt(pointer), () => pointer);
    }
    return pointers;
  }();

  @override
  Uint8List convert(String input) {
    final out = BytesBuilder(copy: false);
    for (final rune in input.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      if (rune == 0x20AC) {
        out.addByte(0x80);
        continue;
      }
      // U+E5E5 在码表里，但 WHATWG 规定 gbk 编码器不输出它
      final pointer = rune == 0xE5E5 ? null : _pointers[rune];
      if (pointer == null) {
        out.addByte(0x3F);
        continue;
      }
      final trail = pointer % 190;
      out
        ..addByte(pointer ~/ 190 + 0x81)
        ..addByte(trail + (trail < 0x3F ? 0x40 : 0x41));
    }
    return out.takeBytes();
  }
}
