import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:rule_engine/src/js/java_rsa.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/java_rsa_cases.json').readAsStringSync()) as Map;
  final encoded = base64Decode(fixture['pkcs8'] as String);

  test('RSA PKCS8 独立副本与 SHA256WithRSA 签名匹配 JDK 22', () {
    final input = Uint8List.fromList(encoded);
    final key = javaRsaPrivateKey(input);
    input.fillRange(0, input.length, 0);
    expect(key, encoded);
    for (final entry in fixture['cases'] as List) {
      final bytes = utf8.encode(entry['text'] as String);
      expect(base64Encode(javaRsaSign(key, bytes)), entry['signature']);
      expect(base64Encode(javaRsaSign(key, bytes)), entry['signature']);
    }
  });

  test('拒绝截断 DER、额外数据、PKCS1 裸密钥、EC 算法和缺字段', () {
    final outer = ASN1Parser(encoded).nextObject() as ASN1Sequence;
    final inner = (outer.elements![2] as ASN1OctetString).octets!;
    for (final bad in <List<int>>[
      [],
      [0x30, 0],
      encoded.sublist(0, encoded.length - 1),
      [...encoded, 0],
      inner,
      base64Decode(fixture['ecPkcs8'] as String),
      ASN1Sequence(elements: outer.elements!.sublist(0, 2)).encode(),
      ASN1Sequence(elements: [ASN1Integer(BigInt.one), ...outer.elements!.skip(1)]).encode(),
      [0x30, 0x80, ...encoded.sublist(4), 0, 0],
    ]) {
      expect(() => javaRsaPrivateKey(bad), throwsA(isA<CryptoException>()));
      expect(() => javaRsaSign(bad, [1]), throwsA(isA<CryptoException>()));
    }
  });

  test('拒绝错误参数、RSA 多素数版本、负整数和损坏 CRT，不静默重算', () {
    final outer = ASN1Parser(encoded).nextObject() as ASN1Sequence;
    final inner =
        ASN1Parser(Uint8List.fromList((outer.elements![2] as ASN1OctetString).octets!)).nextObject() as ASN1Sequence;
    Uint8List replaceInner(int index, BigInt value) {
      final fields = [...inner.elements!];
      fields[index] = ASN1Integer(value);
      return ASN1Sequence(
        elements: [
          outer.elements![0],
          outer.elements![1],
          ASN1OctetString(octets: ASN1Sequence(elements: fields).encode()),
        ],
      ).encode();
    }

    for (final index in [0, 1, 2, 3, 4, 5, 6, 7, 8]) {
      final original = (inner.elements![index] as ASN1Integer).integer!;
      expect(() => javaRsaPrivateKey(replaceInner(index, original + BigInt.one)), throwsA(isA<CryptoException>()));
    }
    expect(() => javaRsaPrivateKey(replaceInner(1, -BigInt.one)), throwsA(isA<CryptoException>()));
    final algorithm = outer.elements![1] as ASN1Sequence;
    final invalidParameters = ASN1Sequence(
      elements: [
        outer.elements![0],
        ASN1Sequence(elements: [algorithm.elements![0], ASN1Integer(BigInt.zero)]),
        outer.elements![2],
      ],
    ).encode();
    expect(() => javaRsaPrivateKey(invalidParameters), throwsA(isA<CryptoException>()));
  });

  test('rsaEncryption AlgorithmIdentifier 缺省 NULL 与 JDK 接受的形式兼容', () {
    final outer = ASN1Parser(encoded).nextObject() as ASN1Sequence;
    final algorithm = outer.elements![1] as ASN1Sequence;
    final noNull = ASN1Sequence(
      elements: [
        outer.elements![0],
        ASN1Sequence(elements: [algorithm.elements![0]]),
        outer.elements![2],
      ],
    ).encode();
    expect(base64Encode(javaRsaSign(javaRsaPrivateKey(noNull), [])), (fixture['cases'] as List).first['signature']);
  });
}
