import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/source/book_source.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> source(String url, [Map<String, Object?> extra = const {}]) => {
    'bookSourceUrl': url,
    'bookSourceName': '书源 $url',
    ...extra,
  };

  test('数组载入', () {
    final result = loadBookSources(
      jsonEncode([
        source('https://a.com', {
          'ruleSearch': {'bookList': 'class.item'},
        }),
        source('https://b.com'),
        source('https://c.com'),
      ]),
    );
    expect(result.sources.map((s) => s.bookSourceUrl), ['https://a.com', 'https://b.com', 'https://c.com']);
    expect(result.sources.first.ruleSearch['bookList'], 'class.item');
    expect(result.skipped, isEmpty);
  });

  test('单个书源对象', () {
    final result = loadBookSources(jsonEncode(source('https://a.com')));
    expect(result.sources.single.bookSourceName, '书源 https://a.com');
  });

  test('规则组是字符串', () {
    final result = loadBookSources(jsonEncode(source('https://a.com', {'ruleSearch': '{"bookList":"class.item"}'})));
    expect(result.sources.single.ruleSearch['bookList'], 'class.item');
  });

  test('缺失的字段和规则组按空处理', () {
    final book = loadBookSources(jsonEncode(source('https://a.com'))).sources.single;
    expect(book.searchUrl, isNull);
    expect(book.ruleToc['chapterList'], isNull);
    expect(book.bookSourceType, BookSourceType.text);
    // MD3 的构造器默认值
    expect(book.enabledCookieJar, isTrue);
  });

  test('规则值按 MD3 转成字符串', () {
    final book = loadBookSources(
      jsonEncode(
        source('https://a.com', {
          'bookSourceType': 3,
          'enabledCookieJar': false,
          'ruleToc': {'isVolume': 1, 'chapterList': null, 'x': {'a': 1}},
        }),
      ),
    ).sources.single;
    expect(book.bookSourceType, BookSourceType.file);
    expect(book.enabledCookieJar, isFalse);
    expect(book.ruleToc['isVolume'], '1');
    expect(book.ruleToc['chapterList'], isNull);
    expect(book.ruleToc['x'], '{"a":1}');
    expect(book.ruleToc.field('isVolume'), 'ruleToc.isVolume');
  });

  test('保留未知字段', () {
    final original = source('https://a.com', {
      'customOrder': 7,
      'exploreUrl': '玄幻::/c/1.html',
      'ruleReview': {'x': 'y'},
    });
    final book = loadBookSources(jsonEncode([original])).sources.single;
    expect(jsonEncode(book.toJson()), jsonEncode(original));
  });

  test('混入无效条目', () {
    final result = loadBookSources(
      jsonEncode([
        source('https://a.com'),
        {'bookSourceName': '没有地址'},
        source('https://b.com'),
        '不是对象',
        source('   '),
      ]),
    );
    expect(result.sources, hasLength(2));
    expect(result.skipped, [
      (index: 1, reason: '缺少书源地址'),
      (index: 3, reason: '不是 JSON 对象'),
      (index: 4, reason: '缺少书源地址'),
    ]);
  });

  test('混入订阅源：原因是订阅源', () {
    final result = loadBookSources(
      jsonEncode([
        source('https://a.com'),
        {'sourceUrl': 'https://rss.com', 'sourceName': '订阅'},
      ]),
    );
    expect(result.sources, hasLength(1));
    expect(result.skipped, [(index: 1, reason: rssSourceSkipReason)]);
  });

  test('网址列表：只带回网址，不载入书源；同时有书源地址也按网址列表处理', () {
    final result = loadBookSources(
      jsonEncode({
        'bookSourceUrl': 'https://a.com',
        'sourceUrls': ['https://a.com/1.json', 'https://a.com/2.json', 3],
      }),
    );
    expect(result.sources, isEmpty);
    expect(result.skipped, isEmpty);
    expect(result.sourceUrls, ['https://a.com/1.json', 'https://a.com/2.json']);
  });

  test('不是合法 JSON 时报错', () {
    expect(() => loadBookSources('[{'), throwsFormatException);
    expect(() => loadBookSources('"x"'), throwsFormatException);
  });

  test('BOM 和宽松 JSON', () {
    expect(loadBookSources("﻿[{bookSourceUrl:'https://a.com'}]").sources, hasLength(1));
  });

  // 对照 source-check 的统计：LEGADO_SOURCES_DIR 指向 aoaostar/legado 的 sources 目录
  final dir = Platform.environment['LEGADO_SOURCES_DIR'];
  test('载入 aoaostar 全量书源', () {
    var loaded = 0;
    var skipped = 0;
    var unparsable = 0;
    for (final file in Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final BookSourceLoadResult result;
      try {
        result = loadBookSources(file.readAsStringSync());
      } on FormatException {
        unparsable++;
        continue;
      }
      loaded += result.sources.length;
      skipped += result.skipped.length;
    }
    printOnFailure('载入 $loaded，跳过 $skipped，无法解析的文件 $unparsable');
    // source-check 2026-10-11 的统计：书源 3310 + 重复 5441，跳过 309
    expect(loaded, 3310 + 5441);
    expect(skipped, 309);
  }, skip: dir == null ? '没有设置 LEGADO_SOURCES_DIR' : false);
}
