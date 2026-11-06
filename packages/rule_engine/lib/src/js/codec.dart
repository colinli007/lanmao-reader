import 'dart:convert';
import 'dart:typed_data';

import '../text/charsets.dart';

/// 书源 JS 里的编码函数：两套 Base64、十六进制、字符集。语义照 MD3（legado-with-MD3 d1b488b）：
/// 不带 flags 的 `base64Decode` 用 Hutool 的宽松解码，带 flags 的和 `base64DecodeToByteArray`、`base64Encode`
/// 用 Android 的 `android.util.Base64`。期望值由 `tool/jsoup_oracle/CodecOracle.java` 生成。

/// Android Base64 的 flags。
const int base64NoPadding = 1;
const int base64NoWrap = 2;
const int base64Crlf = 4;
const int base64UrlSafe = 8;

/// Java `Base64.getDecoder()`：标准字母表、不接受空白；末尾 padding 可以省略。
/// Android 解码状态机的分组和 padding 规则相同，先拒绝它会忽略的字符。
Uint8List base64DecodeJava(String text) {
  if (text.codeUnits.any((byte) => _androidValue(byte, false) == _skip)) {
    throw const FormatException('Illegal base64 character');
  }
  return base64DecodeAndroid(text, 0);
}

/// Hutool `Base64.decode`（MD3 先去掉空白再调用它）：标准和 URL 安全两套字符都认，`=` 和其它字符一律跳过，
/// 输入结束时补齐。码表只到 `z`，`{|}~` 和 DEL 会让 Hutool 数组越界，这里同样以错误结束。
Uint8List base64DecodeLenient(String text) {
  final out = BytesBuilder(copy: false);
  final input = utf8.encode(text);
  var pos = 0;

  // 取下一个有效字符的值，没有了返回 -1（相当于 Hutool 的 PADDING）
  int next() {
    while (pos < input.length) {
      final byte = input[pos++];
      if (byte >= 0x80) continue;
      if (byte > 0x7A) throw const FormatException('Base64 解码失败：码表越界');
      final value = _lenientTable[byte];
      if (value >= 0) return value;
    }
    return -1;
  }

  while (pos < input.length) {
    final s0 = next();
    final s1 = next();
    final s2 = next();
    final s3 = next();
    if (s1 != -1) out.addByte(((s0 << 2) | (s1 >> 4)) & 0xFF);
    if (s2 != -1) out.addByte((((s1 & 0xF) << 4) | (s2 >> 2)) & 0xFF);
    if (s3 != -1) out.addByte((((s2 & 3) << 6) | s3) & 0xFF);
  }
  return out.takeBytes();
}

/// Hutool 的码表：`+` 和 `-` 都是 62，`/` 和 `_` 都是 63，其余为 -1（`=` 也跳过）。
final List<int> _lenientTable = () {
  final table = List<int>.filled(0x7B, -1);
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (var i = 0; i < alphabet.length; i++) {
    table[alphabet.codeUnitAt(i)] = i;
  }
  table[0x2B] = table[0x2D] = 62;
  table[0x2F] = table[0x5F] = 63;
  return table;
}();

/// Android `Base64.decode(str, flags)`：只有 [base64UrlSafe] 影响解码（选用 `-_` 还是 `+/`）；
/// 字母表以外的字符跳过，`=` 只能出现在末尾的合法位置，否则以 [FormatException] 结束（Android 的 bad base-64）。
Uint8List base64DecodeAndroid(String text, int flags) {
  final urlSafe = flags & base64UrlSafe != 0;
  final out = BytesBuilder(copy: false);
  var state = 0;
  var value = 0;
  for (final byte in utf8.encode(text)) {
    final d = _androidValue(byte, urlSafe);
    if (d == _skip) continue;
    switch (state) {
      case 0 || 1:
        if (d < 0) throw const FormatException('bad base-64');
        value = (value << 6) | d;
        state++;
      case 2:
        if (d == _equals) {
          out.addByte((value >> 4) & 0xFF);
          state = 4;
        } else {
          value = (value << 6) | d;
          state = 3;
        }
      case 3:
        if (d == _equals) {
          out
            ..addByte((value >> 10) & 0xFF)
            ..addByte((value >> 2) & 0xFF);
          state = 5;
        } else {
          value = (value << 6) | d;
          out
            ..addByte((value >> 16) & 0xFF)
            ..addByte((value >> 8) & 0xFF)
            ..addByte(value & 0xFF);
          value = 0;
          state = 0;
        }
      case 4:
        if (d != _equals) throw const FormatException('bad base-64');
        state = 5;
      default:
        // 结束之后（state 5）又出现了数据或 =
        throw const FormatException('bad base-64');
    }
  }
  switch (state) {
    case 1 || 4:
      throw const FormatException('bad base-64');
    case 2:
      out.addByte((value >> 4) & 0xFF);
    case 3:
      out
        ..addByte((value >> 10) & 0xFF)
        ..addByte((value >> 2) & 0xFF);
  }
  return out.takeBytes();
}

const int _skip = -1;
const int _equals = -2;

int _androidValue(int byte, bool urlSafe) {
  if (byte >= 0x41 && byte <= 0x5A) return byte - 0x41;
  if (byte >= 0x61 && byte <= 0x7A) return byte - 0x61 + 26;
  if (byte >= 0x30 && byte <= 0x39) return byte - 0x30 + 52;
  if (byte == 0x3D) return _equals;
  if (byte == (urlSafe ? 0x2D : 0x2B)) return 62;
  if (byte == (urlSafe ? 0x5F : 0x2F)) return 63;
  return _skip;
}

/// Android `Base64.encodeToString(bytes, flags)`：默认每 76 个字符换行并以换行结尾（[base64NoWrap] 去掉），
/// [base64Crlf] 用 `\r\n`，[base64NoPadding] 去掉 `=`，[base64UrlSafe] 用 `-_`。
String base64EncodeAndroid(List<int> bytes, int flags) {
  final alphabet = flags & base64UrlSafe != 0 ? _urlSafeAlphabet : _standardAlphabet;
  final padding = flags & base64NoPadding == 0;
  final newline = flags & base64NoWrap != 0 ? '' : (flags & base64Crlf != 0 ? '\r\n' : '\n');
  final out = StringBuffer();
  var groups = 0;
  var i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    final v = (bytes[i] & 0xFF) << 16 | (bytes[i + 1] & 0xFF) << 8 | (bytes[i + 2] & 0xFF);
    out
      ..write(alphabet[v >> 18 & 0x3F])
      ..write(alphabet[v >> 12 & 0x3F])
      ..write(alphabet[v >> 6 & 0x3F])
      ..write(alphabet[v & 0x3F]);
    if (++groups == 19) {
      out.write(newline);
      groups = 0;
    }
  }
  final rest = bytes.length - i;
  if (rest == 1) {
    final v = (bytes[i] & 0xFF) << 4;
    out
      ..write(alphabet[v >> 6 & 0x3F])
      ..write(alphabet[v & 0x3F])
      ..write(padding ? '==' : '')
      ..write(newline);
  } else if (rest == 2) {
    final v = (bytes[i] & 0xFF) << 10 | (bytes[i + 1] & 0xFF) << 2;
    out
      ..write(alphabet[v >> 12 & 0x3F])
      ..write(alphabet[v >> 6 & 0x3F])
      ..write(alphabet[v & 0x3F])
      ..write(padding ? '=' : '')
      ..write(newline);
  } else if (groups > 0) {
    // 正好以整组结束，最后一行还没换行
    out.write(newline);
  }
  return out.toString();
}

const String _standardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const String _urlSafeAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// 标准 Base64，带 `=`、不换行（加密结果的 `encryptBase64`、`digestBase64Str`）。
String base64EncodeStandard(List<int> bytes) => base64EncodeAndroid(bytes, base64NoWrap);

/// 小写十六进制。
String hexEncode(List<int> bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    out.write((byte & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// 十六进制解码：长度必须是偶数，每两个字符按 Kotlin 的 `toInt(16)` 解析（大小写都认，可以带正负号）。
Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) throw const FormatException('Hex input must contain an even number of characters');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final pair = hex.substring(i * 2, i * 2 + 2);
    if (!_kotlinHexInt.hasMatch(pair)) throw FormatException('For input string: "$pair"');
    out[i] = int.parse(pair, radix: 16) & 0xFF;
  }
  return out;
}

final RegExp _kotlinHexInt = RegExp(r'^[+-]?[0-9A-Fa-f]+$');

/// 全是十六进制字符（含空串），MD3 的 `String.isHex()`。
bool isHex(String text) => !text.codeUnits.any(
      (c) => !((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)),
    );

/// 按 Java 的字符集名取编码，不支持时以 [ArgumentError] 结束（Java 的 UnsupportedCharsetException）。
Encoding javaCharset(String name) => charsetByName(name) ?? (throw ArgumentError('不支持的字符集：$name'));

/// Java `String.getBytes(charset)`。
Uint8List stringToBytes(String text, String charset) =>
    Uint8List.fromList(encodeLikeJava(text, javaCharset(charset)));

/// Java `new String(bytes, charset)`。
String bytesToString(List<int> bytes, String charset) =>
    decodeLikeJava([for (final b in bytes) b & 0xFF], javaCharset(charset));

/// `java.encodeURI`：Java `URLEncoder.encode`，字符集不认识时返回空串（MD3 吞掉了异常）。
String formEncode(String text, String charset) {
  final encoding = charsetByName(charset);
  return encoding == null ? '' : urlEncodeLikeJava(text, encoding);
}
