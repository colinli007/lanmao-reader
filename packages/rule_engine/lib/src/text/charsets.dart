import 'dart:convert';

import 'gbk.dart';

/// 按 Java 的字符集名找编码器，支持 UTF-8、GBK 一族（GBK 兼容 GB2312）、GB18030 和 ISO-8859-1。
/// 不支持的名字返回 null。
Encoding? charsetByName(String name) => switch (name.trim().toLowerCase()) {
  // Android/ICU 也接受西瓜原始规则使用的 UTF_8 别名。
  'utf-8' || 'utf8' || 'utf_8' => utf8,
  'gbk' || 'gb2312' || 'x-gbk' || 'cp936' || 'windows-936' || 'euc-cn' => gbk,
  'gb18030' => gb18030,
  'iso-8859-1' || 'iso8859-1' || 'latin1' || 'us-ascii' || 'ascii' => latin1,
  _ => null,
};

/// 用 [encoding] 编码，和 Java 的 `String.getBytes(charset)` 一样把编不了的字符换成 `?`。
/// Java 按 UTF-16 单元逐个编码时，落单的代理项也是编不了的字符。
List<int> encodeLikeJava(String text, Encoding encoding) {
  if (identical(encoding, utf8)) {
    final out = <int>[];
    for (final rune in text.runes) {
      // String.runes 把落单的代理项原样给出，Java 把它编成 ?
      out.addAll(rune >= 0xD800 && rune <= 0xDFFF ? const [0x3F] : utf8.encode(String.fromCharCode(rune)));
    }
    return out;
  }
  if (identical(encoding, latin1)) {
    return [for (final c in text.codeUnits) c <= 0xFF ? c : 0x3F];
  }
  return encoding.encode(text);
}

const String _hexUpper = '0123456789ABCDEF';

/// Java `URLEncoder.encode`：字母数字和 `.-*_` 保留，空格转成 `+`，其余按字符集转成大写的 `%XX`。
String urlEncodeLikeJava(String text, Encoding encoding) {
  final out = StringBuffer();
  final runes = text.runes.toList();
  var i = 0;
  while (i < runes.length) {
    final c = runes[i];
    if (_isFormSafe(c)) {
      out.writeCharCode(c);
      i++;
    } else if (c == 0x20) {
      out.write('+');
      i++;
    } else {
      // 连续的需要编码的字符一起转成字节
      final start = i;
      while (i < runes.length && !_isFormSafe(runes[i]) && runes[i] != 0x20) {
        i++;
      }
      for (final b in encodeLikeJava(String.fromCharCodes(runes.sublist(start, i)), encoding)) {
        out
          ..write('%')
          ..write(_hexUpper[b >> 4])
          ..write(_hexUpper[b & 0xF]);
      }
    }
  }
  return out.toString();
}

bool _isFormSafe(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2E || c == 0x2D || c == 0x2A || c == 0x5F;

/// Java 的 `new String(bytes, charset)`：解不了的字节换成 U+FFFD。
String decodeLikeJava(List<int> bytes, Encoding encoding) =>
    identical(encoding, utf8) ? utf8.decode(bytes, allowMalformed: true) : encoding.decode(bytes);
