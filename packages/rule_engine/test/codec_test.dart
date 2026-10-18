import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/text/gbk.dart';
import 'package:test/test.dart';

/// 期望值由 tool/jsoup_oracle/run_codec.py 生成（JDK / Hutool / AOSP android.util.Base64）。
final List<Map<String, Object?>> _cases = [
  for (final c in (jsonDecode(File('test/fixtures/codec_cases.json').readAsStringSync()) as Map)['cases'] as List)
    (c as Map).cast<String, Object?>(),
];

void main() {
  final ops = <String, String Function(List<String>)>{
    'base64Lenient': (a) => hexEncode(base64DecodeLenient(a[0])),
    'base64Decode': (a) => hexEncode(base64DecodeAndroid(a[0], int.parse(a[1]))),
    'base64Encode': (a) => base64EncodeAndroid(hexDecode(a[0]), int.parse(a[1])),
    'strToBytes': (a) => hexEncode(stringToBytes(a[0], a[1])),
    'bytesToStr': (a) => bytesToString(hexDecode(a[0]), a[1]),
    'encodeURI': (a) => formEncode(a[0], a[1]),
  };

  for (final c in _cases.where((c) => ops.containsKey(c['op']))) {
    final args = (c['args'] as List).cast<String>();
    test('${c['op']}：${c['note']}', () {
      final run = ops[c['op']]!;
      if (c.containsKey('error')) {
        expect(() => run(args), throwsA(anything), reason: '期望 ${c['error']}');
      } else {
        expect(run(args), c['expected']);
      }
    });
  }

  test('Hutool 码表越界的字符以错误结束', () {
    expect(() => base64DecodeLenient('YQ{'), throwsFormatException);
  });

  test('十六进制', () {
    expect(hexEncode([0, 15, 255, -1]), '000fffff');
    expect(hexDecode('0fFF'), [15, 255]);
    expect(() => hexDecode('abc'), throwsFormatException);
    expect(() => hexDecode('zz'), throwsFormatException);
    expect(() => hexDecode(' f'), throwsFormatException);
    expect(isHex(''), isTrue);
    expect(isHex('09afAF'), isTrue);
    expect(isHex('0g'), isFalse);
  });

  test('GB18030 四字节往返', () {
    const text = '𠀀€é\u0080';
    expect(gb18030.decode(gb18030.encode(text)), text);
    expect(gb18030.encode('𠀀'), [0x95, 0x32, 0x82, 0x36]);
    expect(gbk.encode('𠀀'), [0x3F]);
  });
}
