import 'dart:convert';

import 'gbk.dart';

/// 按 Java 的字符集名找编码器，支持 UTF-8、GBK 一族（GBK 兼容 GB2312，GB18030 只支持双字节部分）
/// 和 ISO-8859-1。不支持的名字返回 null。
Encoding? charsetByName(String name) => switch (name.trim().toLowerCase()) {
  'utf-8' || 'utf8' => utf8,
  'gbk' || 'gb2312' || 'gb18030' || 'x-gbk' || 'cp936' || 'windows-936' || 'euc-cn' => gbk,
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
