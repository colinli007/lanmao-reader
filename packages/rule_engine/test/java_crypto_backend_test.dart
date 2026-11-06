import 'dart:convert';

import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:test/test.dart';

void main() {
  // JDK 22 java.util.Base64.getDecoder() 的实际输出，包括未使用位不为零的输入。
  test('Java basic Base64 允许省略 padding，拒绝 Android 宽松字符', () {
    for (final text in ['', 'Zg', 'Zh', 'Zg==', 'Zh==', 'Zm8', 'Zm9']) {
      expect(
        base64DecodeJava(text),
        text.isEmpty ? [] : utf8.encode(text.startsWith('Zm') ? 'fo' : 'f'),
      );
    }
    for (final text in [
      'a',
      'Zg=',
      'Zg===',
      'Zg==\n',
      ' Zg==',
      '-_8=',
      'AA=A',
      'Zg==é',
    ]) {
      expect(() => base64DecodeJava(text), throwsFormatException, reason: text);
    }
    expect(base64DecodeJava('/w=='), [255]);
  });

  final key = utf8.encode('242ccb8230d709e1');
  final iv = utf8.encode('0123456789abcdef');
  // 由 JDK 22 javax.crypto.Cipher 生成，避免仅以本实现往返验证。
  const vectors = {
    'AES': '4aa2cb0fe9d34f493885244d0d89dc006654e6f77d967de49e6c955465ec5236',
    'AES/CBC/PKCS5Padding':
        'c100242565123289edfaa18939425cec72eacd541ffa7033cef0ee47fd5d319c',
    'AES/CBC/NoPadding': '5731e37002e6b65d9bf9d60303abd770',
  };
  for (final vector in vectors.entries) {
    test('Java Cipher ${vector.key} 与 JDK 一致', () {
      final selectedIv = vector.key.contains('CBC') ? iv : null;
      final plain = utf8.encode(
        vector.key.contains('NoPadding') ? '0123456789abcdef' : '星空小说：你好🌙',
      );
      expect(
        hexEncode(javaAesCipher(vector.key, key, selectedIv, 1, plain)),
        vector.value,
      );
      expect(
        javaAesCipher(vector.key, key, selectedIv, 2, hexDecode(vector.value)),
        plain,
      );
      expect(javaAesCipher(vector.key, key, selectedIv, 2, []), isEmpty);
    });
  }

  test('PKCS7 为 Android 支持的 PKCS5 等价名称', () {
    expect(
      hexEncode(
        javaAesCipher(
          'AES/CBC/PKCS7Padding',
          key,
          iv,
          1,
          utf8.encode('星空小说：你好🌙'),
        ),
      ),
      vectors['AES/CBC/PKCS5Padding'],
    );
  });

  test('Java Cipher 拒绝错误参数、非整块密文和损坏 padding', () {
    for (final operation in <void Function()>[
      () => javaAesCipher('DES', key, null, 1, []),
      () => javaAesCipher('AES/GCM/NoPadding', key, iv, 1, []),
      () => javaAesCipher('AES', key, null, 3, []),
      () => javaAesCipher('AES', [1], null, 1, []),
      () => javaAesCipher('AES', key, iv, 1, []),
      () => javaAesCipher('AES/CBC/PKCS5Padding', key, null, 2, []),
      () => javaAesCipher('AES/CBC/PKCS5Padding', key, [1], 2, []),
      () => javaAesCipher('AES', key, null, 2, [1]),
      () => javaAesCipher('AES/ECB/NoPadding', key, null, 1, [1]),
      () => javaAesCipher('AES', key, null, 2, List.filled(16, 0)),
    ]) {
      expect(operation, throwsA(isA<CryptoException>()));
    }
  });

  test('单次 Cipher 操作复制输入并在相同初始化参数下可重复执行', () {
    final input = hexDecode(vectors['AES/CBC/PKCS5Padding']!);
    final expected = utf8.encode('星空小说：你好🌙');
    expect(javaAesCipher('AES/CBC/PKCS5Padding', key, iv, 2, input), expected);
    expect(javaAesCipher('AES/CBC/PKCS5Padding', key, iv, 2, input), expected);
    expect(hexEncode(input), vectors['AES/CBC/PKCS5Padding']);
    expect(iv, utf8.encode('0123456789abcdef'));
  });

  test('随机 IV 为独立的 16 字节缓冲区', () {
    final first = javaCipherRandomIv();
    final second = javaCipherRandomIv();
    expect(first, hasLength(16));
    expect(second, hasLength(16));
    expect(identical(first, second), isFalse);
  });
}
