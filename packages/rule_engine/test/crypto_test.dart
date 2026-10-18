import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:test/test.dart';

/// 期望值由 tool/jsoup_oracle/run_codec.py 用 JDK 生成。
final List<Map<String, Object?>> _cases = [
  for (final c in (jsonDecode(File('test/fixtures/codec_cases.json').readAsStringSync()) as Map)['cases'] as List)
    (c as Map).cast<String, Object?>(),
];

String _hex(String text) => hexEncode(utf8.encode(text));

SymmetricCrypto _crypto(List<String> a) {
  final crypto = SymmetricCrypto(a[0], hexDecode(a[1]));
  return a[2].isEmpty ? crypto : crypto.setIv(hexDecode(a[2]));
}

void main() {
  final ops = <String, String Function(List<String>)>{
    'digest': (a) => hexEncode(digest(a[0], utf8.encode(a[1]))),
    'hmac': (a) => hexEncode(hmac(a[0], utf8.encode(a[1]), utf8.encode(a[2]))),
    'cipher': (a) {
      final data = hexDecode(a[4]);
      return hexEncode(a[3] == 'encrypt' ? _crypto(a).encrypt(data) : _crypto(a).decrypt(data));
    },
  };

  for (final c in _cases.where((c) => ops.containsKey(c['op']))) {
    final args = (c['args'] as List).cast<String>();
    test('${c['op']}：${c['note']}', () {
      final run = ops[c['op']]!;
      if (c.containsKey('error')) {
        expect(() => run(args), throwsA(isA<CryptoException>()), reason: '期望 ${c['error']}');
        return;
      }
      expect(run(args), c['expected']);
      // 加密结果再解密，回到原文（解密方向用 JDK 的密文验证）
      if (c['op'] == 'cipher' && args[3] == 'encrypt') {
        expect(hexEncode(_crypto(args).decrypt(hexDecode(c['expected'] as String))), args[4]);
      }
    });
  }

  Map<String, Object?> fixture(String note) => _cases.firstWhere((c) => c['note'] == note);

  test('AES 默认 ECB：与 JDK 的 AES/ECB/PKCS5Padding 一致', () {
    final expected = fixture('加密：AES 默认 ECB（规格场景）')['expected'] as String;
    final crypto = SymmetricCrypto('AES', utf8.encode('1234567890123456'));
    expect(base64EncodeStandard(crypto.encrypt(utf8.encode('三体'))), base64EncodeStandard(hexDecode(expected)));
  });

  test('decrypt 文本：十六进制和宽松 Base64 自动识别', () {
    final expected = fixture('加密：AES 默认 ECB（规格场景）')['expected'] as String;
    final crypto = SymmetricCrypto('AES', utf8.encode('1234567890123456'));
    expect(utf8.decode(crypto.decryptText(expected)), '三体');
    expect(utf8.decode(crypto.decryptText(expected.toUpperCase())), '三体');
    final base64 = base64EncodeStandard(hexDecode(expected));
    expect(utf8.decode(crypto.decryptText(base64.replaceAll('=', ''))), '三体');
  });

  test('AES 密钥长度在第一次使用时才报错', () {
    final crypto = SymmetricCrypto('AES', utf8.encode('short'));
    expect(() => crypto.encrypt([1]), throwsA(isA<CryptoException>()));
  });

  test('不支持的变换在创建时报错', () {
    expect(() => SymmetricCrypto('AES/GCM/NoPadding', utf8.encode('1234567890123456')), throwsA(isA<CryptoException>()));
    expect(() => SymmetricCrypto('AES/ECB/ZeroPadding', utf8.encode('1234567890123456')), throwsA(isA<CryptoException>()));
    expect(() => SymmetricCrypto('RC4', utf8.encode('k')), throwsA(isA<CryptoException>()));
  });

  test('没有密钥时用随机密钥，自己加密自己能解', () {
    final crypto = SymmetricCrypto('DESede', null);
    expect(utf8.decode(crypto.decrypt(crypto.encrypt(utf8.encode('三体')))), '三体');
  });

  group('旧版便捷函数', () {
    const key = '1234567890123456';
    const iv = 'abcdefghijklmnop';
    final cbc = fixture('加密：AES CBC')['expected'] as String; // 明文「三体：地球往事」
    final cbcBase64 = base64EncodeStandard(hexDecode(cbc));
    Object call(String name, List<String> args) => legacyCryptoFunctions[name]!(args);

    test('aesEncodeToString 实际做解密（MD3 的 bug）', () {
      expect(call('aesEncodeToString', [cbcBase64, key, 'AES/CBC/PKCS5Padding', iv]), '三体：地球往事');
    });

    test('aesBase64DecodeToString 与 aesDecodeToString 相同，都自动识别格式', () {
      for (final data in [cbc, cbcBase64]) {
        expect(call('aesBase64DecodeToString', [data, key, 'AES/CBC/PKCS5Padding', iv]), '三体：地球往事');
        expect(call('aesDecodeToString', [data, key, 'AES/CBC/PKCS5Padding', iv]), '三体：地球往事');
      }
    });

    test('加密函数', () {
      expect(call('aesEncodeToBase64String', ['三体：地球往事', key, 'AES/CBC/PKCS5Padding', iv]), cbcBase64);
      expect(call('aesEncodeArgsBase64Str', ['三体：地球往事', key, 'CBC', 'PKCS5Padding', iv]), cbcBase64);
      expect(hexEncode(call('aesEncodeToByteArray', ['三体：地球往事', key, 'AES/CBC/PKCS5Padding', iv]) as List<int>), cbc);
      expect(utf8.decode(call('aesEncodeToBase64ByteArray', ['三体：地球往事', key, 'AES/CBC/PKCS5Padding', iv]) as List<int>),
          cbcBase64);
    });

    test('aesDecodeArgsBase64Str 对密钥和 IV 做 Base64 解码', () {
      final keyBase64 = base64EncodeStandard(utf8.encode(key));
      final ivBase64 = base64EncodeStandard(utf8.encode(iv));
      expect(call('aesDecodeArgsBase64Str', [cbcBase64, keyBase64, 'CBC', 'PKCS5Padding', ivBase64]), '三体：地球往事');
    });

    test('DES 和 3DES', () {
      final des = fixture('加密：DES ECB')['expected'] as String;
      expect(call('desEncodeToBase64String', ['三体：地球往事', '12345678', 'DES/ECB/PKCS5Padding', '']),
          base64EncodeStandard(hexDecode(des)));
      expect(call('desDecodeToString', [des, '12345678', 'DES/ECB/PKCS5Padding', '']), '三体：地球往事');
      final desede = fixture('加密：DESede CBC')['expected'] as String;
      const key24 = '123456789012345678901234';
      expect(call('tripleDESEncodeBase64Str', ['三体：地球往事', key24, 'CBC', 'PKCS5Padding', 'abcdefgh']),
          base64EncodeStandard(hexDecode(desede)));
      expect(call('tripleDESDecodeStr', [desede, key24, 'CBC', 'PKCS5Padding', 'abcdefgh']), '三体：地球往事');
      // ArgsBase64 版本只解码密钥，IV 仍按 UTF-8
      final key24Base64 = base64EncodeStandard(utf8.encode(key24));
      expect(call('tripleDESDecodeArgsBase64Str', [desede, key24Base64, 'CBC', 'PKCS5Padding', 'abcdefgh']), '三体：地球往事');
      expect(call('tripleDESEncodeArgsBase64Str', ['三体：地球往事', key24Base64, 'CBC', 'PKCS5Padding', 'abcdefgh']),
          base64EncodeStandard(hexDecode(desede)));
    });

    test('加解密出错抛出', () {
      expect(() => call('aesDecodeToString', [_hex('x' * 16), key, 'AES/ECB/PKCS5Padding', '']), throwsA(isA<CryptoException>()));
    });
  });
}
