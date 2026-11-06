import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

import 'crypto.dart';

/// KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec)。
/// 保存独立的编码副本，JS 缓存的 PrivateKey 不引用 task 句柄。
Uint8List javaRsaPrivateKey(List<int> encoded) {
  final bytes = Uint8List.fromList(encoded);
  _parsePrivateKey(bytes);
  return bytes;
}

/// Signature.getInstance("SHA256WithRSA")，PKCS#1 v1.5 签名由 PointyCastle 完成。
Uint8List javaRsaSign(List<int> encoded, List<int> data) {
  final key = _parsePrivateKey(Uint8List.fromList(encoded));
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  return signer.generateSignature(Uint8List.fromList(data)).bytes;
}

RSAPrivateKey _parsePrivateKey(Uint8List bytes) {
  try {
    final outer = _sequence(bytes).elements!;
    if (outer.length != 3 || _integer(outer[0]) != BigInt.zero) _invalid();
    final algorithm = outer[1];
    if (algorithm is! ASN1Sequence) _invalid();
    final fields = algorithm.elements!;
    if (fields.isEmpty || fields.length > 2 || fields[0] is! ASN1ObjectIdentifier) _invalid();
    final identifier = ASN1AlgorithmIdentifier.fromSequence(algorithm);
    if (identifier.algorithm.objectIdentifierAsString != '1.2.840.113549.1.1.1' ||
        (identifier.parameters != null && identifier.parameters is! ASN1Null)) {
      _invalid();
    }
    final wrapped = outer[2];
    if (wrapped is! ASN1OctetString || wrapped.tag != 4) _invalid();
    final rsa = _sequence(Uint8List.fromList(wrapped.octets!)).elements!;
    if (rsa.length != 9 || _integer(rsa[0]) != BigInt.zero) _invalid();
    final values = rsa.skip(1).map(_integer).toList();
    if (values.any((value) => value <= BigInt.zero)) _invalid();
    final [n, e, d, p, q, dp, dq, inverse] = values;
    if (n.bitLength < 512 || e <= BigInt.one || e >= n || e.isEven || p <= BigInt.one || q <= BigInt.one) _invalid();
    // RSAPrivateKey 校验 n == p*q；它自行计算 CRT，不能静默忽略损坏的 DER CRT 字段。
    if (dp != d % (p - BigInt.one) || dq != d % (q - BigInt.one) || (inverse * q) % p != BigInt.one) _invalid();
    final phi = (p - BigInt.one) * (q - BigInt.one);
    final lambda = phi ~/ (p - BigInt.one).gcd(q - BigInt.one);
    if ((e * d) % lambda != BigInt.one) _invalid();
    return RSAPrivateKey(n, d, p, q);
  } on CryptoException {
    rethrow;
  } catch (_) {
    // 错误信息不携带书源内嵌私钥或原始 DER。
    _invalid();
  }
}

ASN1Sequence _sequence(Uint8List bytes) {
  final parser = ASN1Parser(bytes);
  final object = parser.nextObject();
  if (object is! ASN1Sequence || object.tag != 0x30 || parser.hasNext()) _invalid();
  _checkDer(object);
  return object;
}

void _checkDer(ASN1Object object) {
  final bytes = object.encodedBytes!;
  if (bytes.length < 2 || bytes[1] == 0x80 || object.totalEncodedByteLength != bytes.length) _invalid();
  if (bytes[1] > 0x80) {
    if (object.valueByteLength! < 128 || bytes[2] == 0) _invalid();
  }
  if (object is ASN1Sequence) {
    for (final child in object.elements!) {
      _checkDer(child);
    }
  }
  if (object is ASN1Null && object.valueByteLength != 0) _invalid();
}

BigInt _integer(ASN1Object object) {
  if (object is! ASN1Integer || object.tag != 2) _invalid();
  final bytes = object.valueBytes!;
  if (bytes.isEmpty || bytes[0] >= 0x80 || (bytes.length > 1 && bytes[0] == 0 && bytes[1] < 0x80)) _invalid();
  return object.integer!;
}

Never _invalid() => throw CryptoException('Invalid RSA PKCS#8 private key');
