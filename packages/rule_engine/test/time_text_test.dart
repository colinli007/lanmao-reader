import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/js/time_text.dart';
import 'package:test/test.dart';

/// 日期格式的期望值由 tool/jsoup_oracle/run_codec.py 用 JDK 的 SimpleDateFormat（简体中文 Locale）生成。
final List<Map<String, Object?>> _cases = [
  for (final c in (jsonDecode(File('test/fixtures/codec_cases.json').readAsStringSync()) as Map)['cases'] as List)
    (c as Map).cast<String, Object?>(),
];

void main() {
  group('timeFormatUTC', () {
    for (final c in _cases.where((c) => c['op'] == 'timeFormatUTC')) {
      final a = (c['args'] as List).cast<String>();
      test(c['note'], () {
        String run() => timeFormatUtc(int.parse(a[0]), a[1], int.parse(a[2]));
        if (c.containsKey('error')) {
          expect(run, throwsFormatException);
        } else {
          expect(run(), c['expected']);
        }
      });
    }

    test('UTC 偏移按毫秒', () {
      expect(timeFormatUtc(0, 'yyyy-MM-dd HH:mm', 28800000), '1970-01-01 08:00');
    });

    test('未闭合的单引号', () {
      expect(() => timeFormatUtc(0, "'abc", 0), throwsFormatException);
    });
  });

  test('timeFormat 用本地时区', () {
    final local = DateTime.fromMillisecondsSinceEpoch(1700000000123);
    String two(int v) => v.toString().padLeft(2, '0');
    expect(timeFormat(1700000000123),
        '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}');
  });

  group('toNumChapter', () {
    const cases = {
      '正文 第一百零五章 风起': '第105章',
      '第十章': '第10章',
      '第二十五章 归来': '第25章',
      '第一千二章': '第1200章',
      '第一零二五章': '第1025章',
      '第两千零一十章': '第2010章',
      '第壹佰贰拾叁章': '第123章',
      '第３２章': '第32章',
      '第 12 章': '第12章',
      '第十二回章': '第-1章',
      '第一万零一章': '第10001章',
      '第三亿章': '第300000000章',
      '序章 开始': '序章 开始',
      '没有章节号': '没有章节号',
      '第一章 第二章': '第1章',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(toNumChapter(input), expected));
    });

    test('「第」和「章」之间跨行时不算', () {
      expect(toNumChapter('第一\n章'), '第一\n章');
    });
  });

  test('randomUUID 是小写的 v4 UUID', () {
    final uuid = randomUuid();
    expect(uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(randomUuid(), isNot(uuid));
  });
}
