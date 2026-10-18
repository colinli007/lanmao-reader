import 'dart:convert';
import 'dart:typed_data';

import 'gbk_table.dart';

/// GBK 编解码（兼容 GB2312），按 WHATWG Encoding Standard 的 gbk 编码实现，只含单字节和双字节部分。
///
/// 解码时无法识别的字节替换为 U+FFFD；编码时 GBK 里没有的字符替换为 `?`，和 Java 的 `getBytes("GBK")` 一致
/// （Java 把 `€` 编成 A2 E3，不用 WHATWG gbk 编码器的单字节 0x80）。
const GbkCodec gbk = GbkCodec._(fourByte: false);

/// GB18030：GBK 加上 WHATWG gb18030 的四字节部分，所有 Unicode 字符都能编码。
const GbkCodec gb18030 = GbkCodec._(fourByte: true);

final class GbkCodec extends Encoding {
  const GbkCodec._({required this.fourByte});

  final bool fourByte;

  @override
  String get name => fourByte ? 'gb18030' : 'gbk';

  @override
  Converter<List<int>, String> get decoder => GbkDecoder._(fourByte: fourByte);

  @override
  Converter<String, List<int>> get encoder => GbkEncoder._(fourByte: fourByte);
}

final class GbkDecoder extends Converter<List<int>, String> {
  const GbkDecoder._({required this.fourByte});

  final bool fourByte;

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
      } else if (fourByte && _isDigit(input[i])) {
        // 四字节：首字节 81–FE，第二、四字节 30–39，第三字节 81–FE；不完整时首字节算一个错误
        if (i + 2 < input.length && _isLead(input[i + 1]) && _isDigit(input[i + 2])) {
          final pointer = (byte - 0x81) * 12600 + (input[i] - 0x30) * 1260 + (input[i + 1] - 0x81) * 10 + input[i + 2] - 0x30;
          final codePoint = _rangesCodePoint(pointer);
          out.writeCharCode(codePoint ?? 0xFFFD);
          i += 3;
        } else {
          out.writeCharCode(0xFFFD);
        }
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
  const GbkEncoder._({required this.fourByte});

  final bool fourByte;

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
      // U+E5E5 在码表里，但 WHATWG 规定 gbk 编码器不输出它
      final pointer = rune == 0xE5E5 ? null : _pointers[rune];
      if (pointer == null) {
        if (fourByte && rune != 0xE5E5 && !(rune >= 0xD800 && rune <= 0xDFFF)) {
          _addFourBytes(out, _rangesPointer(rune));
        } else {
          out.addByte(0x3F);
        }
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

bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;

bool _isLead(int byte) => byte >= 0x81 && byte <= 0xFE;

void _addFourBytes(BytesBuilder out, int pointer) {
  out
    ..addByte(pointer ~/ 12600 + 0x81)
    ..addByte(pointer % 12600 ~/ 1260 + 0x30)
    ..addByte(pointer % 1260 ~/ 10 + 0x81)
    ..addByte(pointer % 10 + 0x30);
}

/// WHATWG 的 index gb18030 ranges code point。
int? _rangesCodePoint(int pointer) {
  if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) return null;
  if (pointer == 7457) return 0xE7C7;
  var offset = 0;
  var codePointOffset = 0;
  for (var i = 0; i < gb18030Ranges.length; i += 2) {
    if (gb18030Ranges[i] > pointer) break;
    offset = gb18030Ranges[i];
    codePointOffset = gb18030Ranges[i + 1];
  }
  return codePointOffset + pointer - offset;
}

/// WHATWG 的 index gb18030 ranges pointer。
int _rangesPointer(int codePoint) {
  if (codePoint == 0xE7C7) return 7457;
  var offset = 0;
  var pointerOffset = 0;
  for (var i = 0; i < gb18030Ranges.length; i += 2) {
    if (gb18030Ranges[i + 1] > codePoint) break;
    pointerOffset = gb18030Ranges[i];
    offset = gb18030Ranges[i + 1];
  }
  return pointerOffset + codePoint - offset;
}
