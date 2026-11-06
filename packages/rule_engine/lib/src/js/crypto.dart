import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show BlockCipher, Digest, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'codec.dart';

/// 书源 JS 的摘要和对称加解密，语义照 MD3（legado-with-MD3 d1b488b）的 `JsEncodeUtils` 和 `SymmetricCryptoAndroid`。
/// 期望值由 `tool/jsoup_oracle/CodecOracle.java` 用 JDK 生成。出错一律抛 [CryptoException]，在 JS 里是普通错误。
final class CryptoException implements Exception {
  CryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 摘要，算法名按 JCA（`MD5`、`SHA-1`、`SHA-256`…，不区分大小写，`-` 可省略）。
Uint8List digest(String algorithm, List<int> data) {
  final digest = _digest(algorithm.toUpperCase().replaceAll('-', '')) ??
      (throw CryptoException('不支持的摘要算法：$algorithm'));
  return digest.process(Uint8List.fromList(data));
}

/// 已由 JS Cipher.init 保存好参数的单次 JCA AES 操作，不持有 task 句柄。
/// 每次调用从相同 key/IV 开始，对应 doFinal 后回到 init 状态的语义。
Uint8List javaAesCipher(String transformation, List<int> key, List<int>? iv, int mode, List<int> data) {
  final normalized = transformation.toUpperCase();
  final parts = (normalized == 'AES' ? 'AES/ECB/PKCS5PADDING' : normalized).split('/');
  if (parts.length != 3 ||
      parts[0] != 'AES' ||
      !const ['CBC', 'ECB'].contains(parts[1]) ||
      !const ['PKCS5PADDING', 'PKCS7PADDING', 'NOPADDING'].contains(parts[2])) {
    throw CryptoException('不支持的 AES 变换：$transformation');
  }
  if (mode != 1 && mode != 2) throw CryptoException('不支持的 Cipher 模式：$mode');
  if (key.length != 16 && key.length != 24 && key.length != 32) {
    throw CryptoException('Invalid AES key length: ${key.length} bytes');
  }
  if (parts[1] == 'CBC' && (iv == null || iv.length != 16)) {
    throw CryptoException('CBC requires a 16-byte IV');
  }
  if (parts[1] == 'ECB' && iv != null) throw CryptoException('ECB mode cannot use IV');
  final crypto = SymmetricCrypto(transformation, key);
  if (iv != null) crypto.setIv(iv);
  return mode == 1 ? crypto.encrypt(data) : crypto.decrypt(data);
}

/// CBC 加密省略 IV 时由 Cipher.init 生成并保存；getIV 返回其副本。
Uint8List javaCipherRandomIv() => _randomBytes(16);

/// HMAC，算法名按 JCA（`HmacMD5`、`HmacSHA256`…，不区分大小写）。密钥为空时出错（Java 的 `SecretKeySpec` 拒绝空密钥）。
Uint8List hmac(String algorithm, List<int> key, List<int> data) {
  final upper = algorithm.toUpperCase();
  final digest = upper.startsWith('HMAC') ? _digest(upper.substring(4)) : null;
  if (digest == null) throw CryptoException('不支持的 HMAC 算法：$algorithm');
  if (key.isEmpty) throw CryptoException('Empty key');
  final mac = HMac.withDigest(digest)..init(KeyParameter(Uint8List.fromList(key)));
  return mac.process(Uint8List.fromList(data));
}

Digest? _digest(String name) => switch (name) {
  'MD5' => MD5Digest(),
  'SHA' || 'SHA1' => SHA1Digest(),
  'SHA224' => SHA224Digest(),
  'SHA256' => SHA256Digest(),
  'SHA384' => SHA384Digest(),
  'SHA512' => SHA512Digest(),
  _ => null,
};

/// `java.createSymmetricCrypto(变换, 密钥, IV)` 返回的对象。
///
/// - 变换里没有 `/` 时按 `算法/ECB/PKCS5Padding`；支持 AES、DES、DESede，ECB、CBC，PKCS5Padding（PKCS7Padding 视同）、NoPadding。
/// - 密钥为 null 时用随机密钥；DES 超过 8 字节截到 8，DESede 超过 24 字节截到 24（16 字节是两段密钥）；
///   密钥长度不合法（包括 AES 不是 16、24、32）时在第一次加解密时出错，与 Java 的 `Cipher.init` 一致。
/// - 没有 IV 或 ECB 模式时不用 IV；CBC 没有 IV 时加密用随机 IV（结果无法解密），解密出错。
final class SymmetricCrypto {
  SymmetricCrypto(String transformation, List<int>? key) {
    final parts = (transformation.contains('/') ? transformation : '$transformation/ECB/PKCS5Padding').split('/');
    if (parts.length != 3) throw CryptoException('不支持的变换：$transformation');
    _algorithm = switch (parts[0].toUpperCase()) {
      'AES' => _Algorithm.aes,
      'DES' => _Algorithm.des,
      'DESEDE' || 'TRIPLEDES' => _Algorithm.desede,
      _ => throw CryptoException('不支持的算法：${parts[0]}'),
    };
    _cbc = switch (parts[1].toUpperCase()) {
      'ECB' => false,
      'CBC' => true,
      _ => throw CryptoException('不支持的模式：${parts[1]}'),
    };
    _padding = switch (parts[2].toUpperCase()) {
      'PKCS5PADDING' || 'PKCS7PADDING' => true,
      'NOPADDING' => false,
      _ => throw CryptoException('不支持的填充：${parts[2]}'),
    };
    _key = key == null ? _randomBytes(_algorithm.defaultKeyLength) : _normalizedKey(Uint8List.fromList(key));
  }

  late final _Algorithm _algorithm;
  late final bool _cbc;
  late final bool _padding;
  late final Uint8List _key;
  Uint8List? _iv;

  int get _blockSize => _algorithm == _Algorithm.aes ? 16 : 8;

  /// 返回自身，可以链式调用。
  SymmetricCrypto setIv(List<int> iv) {
    _iv = Uint8List.fromList(iv);
    return this;
  }

  Uint8List encrypt(List<int> data) {
    final engine = _engine(forEncryption: true);
    final input = Uint8List.fromList(data);
    final padded = _padding ? _pad(input) : input;
    if (padded.length % _blockSize != 0) throw CryptoException('Input length not multiple of $_blockSize bytes');
    final iv = _cbc ? (_iv ?? _randomBytes(_blockSize)) : null;
    return _process(engine, padded, iv, forEncryption: true);
  }

  Uint8List decrypt(List<int> data) {
    final engine = _engine(forEncryption: false);
    final input = Uint8List.fromList(data);
    if (_cbc && _iv == null) throw CryptoException('Parameters missing');
    if (input.length % _blockSize != 0) {
      throw CryptoException('Input length must be multiple of $_blockSize when decrypting with padded cipher');
    }
    final plain = _process(engine, input, _cbc ? _iv : null, forEncryption: false);
    return _padding && plain.isNotEmpty ? _unpad(plain) : plain;
  }

  /// `decrypt(文本)`：全是十六进制字符且长度为偶数时按十六进制，否则按宽松 Base64。
  Uint8List decryptText(String data) =>
      decrypt(isHex(data) && data.length.isEven ? hexDecode(data) : base64DecodeLenient(data));

  Uint8List _normalizedKey(Uint8List key) => switch (_algorithm) {
    _Algorithm.des when key.length > 8 => key.sublist(0, 8),
    _Algorithm.desede when key.length > 24 => key.sublist(0, 24),
    _ => key,
  };

  BlockCipher _engine({required bool forEncryption}) {
    final Uint8List key;
    final BlockCipher engine;
    switch (_algorithm) {
      case _Algorithm.aes:
        if (_key.length != 16 && _key.length != 24 && _key.length != 32) {
          throw CryptoException('Invalid AES key length: ${_key.length} bytes');
        }
        key = _key;
        engine = AESEngine();
      case _Algorithm.des:
        if (_key.length != 8) throw CryptoException('Wrong key size');
        // 单 DES 等于三段相同密钥的 DESede
        key = Uint8List.fromList([..._key, ..._key, ..._key]);
        engine = DESedeEngine();
      case _Algorithm.desede:
        if (_key.length != 16 && _key.length != 24) throw CryptoException('Invalid key length: ${_key.length} bytes');
        key = _key;
        engine = DESedeEngine();
    }
    if (_cbc && _iv != null && _iv!.length != _blockSize) {
      throw CryptoException('Wrong IV length: must be $_blockSize bytes long');
    }
    return engine..init(forEncryption, KeyParameter(key));
  }

  Uint8List _process(BlockCipher engine, Uint8List input, Uint8List? iv, {required bool forEncryption}) {
    final out = Uint8List(input.length);
    final chain = iv == null ? null : Uint8List.fromList(iv);
    final block = Uint8List(_blockSize);
    for (var offset = 0; offset < input.length; offset += _blockSize) {
      block.setRange(0, _blockSize, input, offset);
      if (chain != null && forEncryption) {
        for (var i = 0; i < _blockSize; i++) {
          block[i] ^= chain[i];
        }
      }
      engine.processBlock(block, 0, out, offset);
      if (chain != null) {
        if (forEncryption) {
          chain.setRange(0, _blockSize, out, offset);
        } else {
          for (var i = 0; i < _blockSize; i++) {
            out[offset + i] ^= chain[i];
          }
          chain.setRange(0, _blockSize, input, offset);
        }
      }
    }
    return out;
  }

  Uint8List _pad(Uint8List data) {
    final count = _blockSize - data.length % _blockSize;
    return Uint8List(data.length + count)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + count, count);
  }

  Uint8List _unpad(Uint8List data) {
    final count = data.last;
    if (count < 1 || count > _blockSize || count > data.length) throw CryptoException('Given final block not properly padded');
    for (var i = data.length - count; i < data.length; i++) {
      if (data[i] != count) throw CryptoException('Given final block not properly padded');
    }
    return data.sublist(0, data.length - count);
  }
}

enum _Algorithm {
  aes(16),
  des(8),
  desede(24);

  const _Algorithm(this.defaultKeyLength);

  final int defaultKeyLength;
}

final Random _random = Random.secure();

Uint8List _randomBytes(int length) => Uint8List.fromList([for (var i = 0; i < length; i++) _random.nextInt(256)]);

/// 旧版便捷函数（MD3 里都已标为过时，内部转调 `createSymmetricCrypto`），参数都是文本：
/// 数据、密钥、变换（或模式和填充）、IV；密钥和 IV 按 UTF-8 转字节，IV 为空串时不用 IV。
/// 按 MD3 的实际行为实现，包括：`aesEncodeToString` 实际做解密；`aesBase64DecodeTo*` 与 `aesDecodeTo*` 相同
/// （都自动识别十六进制和 Base64）；`aesEncodeArgsBase64Str` 不对密钥和 IV 做 Base64 解码；
/// `tripleDESDecodeArgsBase64Str`、`tripleDESEncodeArgsBase64Str` 只解码密钥，IV 仍按 UTF-8。
/// 返回值是文本或字节数组（[Uint8List]）。
final Map<String, Object Function(List<String> args)> legacyCryptoFunctions = {
  'aesDecodeToByteArray': (a) => _crypto(a[2], a[1], a[3]).decryptText(a[0]),
  'aesDecodeToString': (a) => _decryptStr(_crypto(a[2], a[1], a[3]), a[0]),
  'aesBase64DecodeToByteArray': (a) => _crypto(a[2], a[1], a[3]).decryptText(a[0]),
  'aesBase64DecodeToString': (a) => _decryptStr(_crypto(a[2], a[1], a[3]), a[0]),
  'aesDecodeArgsBase64Str': (a) => _decryptStr(
    _cryptoBytes('AES/${a[2]}/${a[3]}', base64DecodeAndroid(a[1], base64NoWrap), base64DecodeAndroid(a[4], base64NoWrap)),
    a[0],
  ),
  'aesEncodeToByteArray': (a) => _crypto(a[2], a[1], a[3]).encrypt(utf8.encode(a[0])),
  'aesEncodeToString': (a) => _decryptStr(_crypto(a[2], a[1], a[3]), a[0]),
  'aesEncodeToBase64ByteArray': (a) => utf8.encode(base64EncodeStandard(_crypto(a[2], a[1], a[3]).encrypt(utf8.encode(a[0])))),
  'aesEncodeToBase64String': (a) => base64EncodeStandard(_crypto(a[2], a[1], a[3]).encrypt(utf8.encode(a[0]))),
  'aesEncodeArgsBase64Str': (a) => base64EncodeStandard(_crypto('AES/${a[2]}/${a[3]}', a[1], a[4]).encrypt(utf8.encode(a[0]))),
  'desDecodeToString': (a) => _decryptStr(_crypto(a[2], a[1], a[3]), a[0]),
  'desBase64DecodeToString': (a) => _decryptStr(_crypto(a[2], a[1], a[3]), a[0]),
  'desEncodeToString': (a) => utf8.decode(_crypto(a[2], a[1], a[3]).encrypt(utf8.encode(a[0])), allowMalformed: true),
  'desEncodeToBase64String': (a) => base64EncodeStandard(_crypto(a[2], a[1], a[3]).encrypt(utf8.encode(a[0]))),
  'tripleDESDecodeStr': (a) => _decryptStr(_crypto('DESede/${a[2]}/${a[3]}', a[1], a[4]), a[0]),
  'tripleDESDecodeArgsBase64Str': (a) =>
      _decryptStr(_cryptoBytes('DESede/${a[2]}/${a[3]}', base64DecodeAndroid(a[1], base64NoWrap), utf8.encode(a[4])), a[0]),
  'tripleDESEncodeBase64Str': (a) =>
      base64EncodeStandard(_crypto('DESede/${a[2]}/${a[3]}', a[1], a[4]).encrypt(utf8.encode(a[0]))),
  'tripleDESEncodeArgsBase64Str': (a) => base64EncodeStandard(
    _cryptoBytes('DESede/${a[2]}/${a[3]}', base64DecodeAndroid(a[1], base64NoWrap), utf8.encode(a[4])).encrypt(utf8.encode(a[0])),
  ),
};

SymmetricCrypto _crypto(String transformation, String key, String iv) =>
    _cryptoBytes(transformation, utf8.encode(key), utf8.encode(iv));

/// `createSymmetricCrypto(变换, 密钥字节, IV 字节)`：IV 为空时不设置。
SymmetricCrypto _cryptoBytes(String transformation, List<int> key, List<int> iv) {
  final crypto = SymmetricCrypto(transformation, key);
  return iv.isEmpty ? crypto : crypto.setIv(iv);
}

String _decryptStr(SymmetricCrypto crypto, String data) => utf8.decode(crypto.decryptText(data), allowMalformed: true);
