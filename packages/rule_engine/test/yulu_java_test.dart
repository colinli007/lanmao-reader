import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:rule_engine/src/js/source_js.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 合集 1329 的雨鹿小说原始 jsLib 和四链路规则；只替换网络响应，不改脚本。
void main() {
  late FakeEnvironment env;
  late BookSource source;
  setUp(() {
    env = FakeEnvironment();
    source = loadBookSources(
      File('test/fixtures/yulu_java_source.json').readAsStringSync(),
    ).sources.single;
  });
  tearDown(() => env.dispose());

  Object? js(String code) =>
      SourceJs.instance.evalSource(SourceTask(env, source), code);

  test('雨鹿字节辅助函数保留所有 256 个值，范围复制后可交回宿主解码', () {
    final bytes = List.generate(256, (i) => i);
    expect(
      js('yuluBytesFromArray(${jsonEncode(bytes)})'),
      List.generate(256, (i) => i.toSigned(8)),
    );
    expect(js('yuluBytesFromRange([0, 127, -128, -1, 12], 1, 4)'), [
      127,
      -128,
      -1,
    ]);
    expect(
      js('java.bytesToStr(yuluBytesFromArray([-28,-72,-83,-26,-106,-121]))'),
      '中文',
    );
  });

  test('雨鹿动态信封解密保留中文和补充平面字符', () {
    const plain = '{"name":"雨鹿测试🚀","text":"中文正文\\n第二段"}';
    final envelope = _envelope(plain);
    expect(js('yuluDecryptEnvelope(java, ${jsonEncode(envelope)})'), plain);
  });

  test('雨鹿原始规则离线跑通搜索、详情、目录和正文', () {
    final date = js('yuluDateStamp()');
    final configUrl =
        'https://conf.wendulou.com/v4/android/com.yuluyuedu.app/new2026?t=$date';
    const searchUrl = 'https://s.yulu.test/v4/1/lists.api?keyword=test&form=1';
    const detailUrl = 'https://d.yulu.test/book/details/v4/1/1234.html';
    const sourcesUrl = 'https://d.yulu.test/book/source/v4/1/1234.html';
    const regularsUrl = 'https://conf.yulu.test/v4/source/site.html';
    const tocUrl =
        'https://catalog.yulu.test/toc/1234.json?yulu_site_id=chosen';
    const chapterUrl =
        'https://chapter.yulu.test/content/1234/1.json?yulu_site_id=chosen';
    final bookData = {
      'book_id': 1234,
      'name': '雨鹿测试🚀',
      'author': '测试作者',
      'intro': '合成测试简介',
      'tags': [
        {'tags_name': '奇幻'},
      ],
      'image': 'covers/1234.jpg',
      'last_chapter': '第二章',
      'word_count': 12000,
    };
    env.respond(
      configUrl,
      _body({
        'urls': {'domain': 'yulu.test'},
      }),
    );
    env.respond(
      searchUrl,
      _body({
        'book': [bookData],
        // 重复项去重，作者的 books 内嵌对象也须跨 ArrayList/JS/Dart 边界保留字段。
        'author': [
          {
            'books': [
              bookData,
              {...bookData, 'book_id': 1235, 'name': '第二本'},
            ],
          },
          '作者建议不应作为书籍',
        ],
      }),
    );
    env.respond(detailUrl, _body(bookData));
    env.respond(
      sourcesUrl,
      _body([
        {'site_id': 'other', 'site_path': '/unused.json', 'choose': '20%'},
        {'site_id': 'chosen', 'site_path': '/toc/1234.json', 'choose': '98%'},
      ]),
    );
    env.respond(
      regularsUrl,
      _body([
        {
          'site_id': 'chosen',
          'regular': [
            {'regular_key': '广告文字', 'regular_value': ''},
          ],
        },
      ]),
    );
    env.respond(
      tocUrl,
      jsonEncode({
        'code': 1,
        'data': [
          {
            'name': _fixed('第一章 起点🚀'),
            'path': '/content/1234/1.json',
            'updated_at': '2026-11-06',
          },
          {'name': _fixed('第二章'), 'path': '/content/1234/2.json'},
        ],
      }),
    );
    env.respond(
      chapterUrl,
      jsonEncode({
        'code': 1,
        'data': {'content': _fixed('中文正文🚀。广告文字\n第二段。')},
      }),
    );

    final books = searchBooks(env, source, 'test');
    expect(books.map((b) => b.name), ['雨鹿测试🚀', '第二本']);
    expect(books.first.author, '测试作者');
    expect(books.first.bookUrl, detailUrl);
    expect(books.first.coverUrl, 'https://res.yulu.test/covers/1234.jpg');
    expect(books.first.kind, '奇幻');

    final book = getBookInfo(env, source, books.first.toBook());
    expect(book.name, '雨鹿测试🚀');
    expect(book.tocUrl, tocUrl);
    expect(book.intro, '合成测试简介');
    final chapters = getChapterList(env, source, book);
    expect(chapters.map((c) => c.title), ['第一章 起点🚀', '第二章']);
    expect(chapters.first.url, chapterUrl);
    final content = getContent(env, source, book, chapters.first);
    expect(content.content, '中文正文🚀。\n　　第二段。');
    expect(env.requests.map((r) => r.url), [
      configUrl,
      searchUrl,
      detailUrl,
      sourcesUrl,
      regularsUrl,
      tocUrl,
      chapterUrl,
    ]);
  });
}

Map<String, Object> _envelope(String plain) {
  final prefix = ascii.encode('0123456789abcdef');
  final suffix = ascii.encode('fedcba9876543210');
  final key = digest('SHA-256', prefix);
  final md5Text = ascii.encode(hexEncode(digest('MD5', suffix)));
  final iv = List.generate(16, (i) => (~(md5Text[i] ^ suffix[i])) & 255);
  final cipher = SymmetricCrypto(
    'AES/CBC/PKCS5Padding',
    key,
  ).setIv(iv).encrypt(utf8.encode(plain));
  return {
    'ver': 1,
    'content': base64Encode([...prefix, ...cipher, ...suffix]),
  };
}

String _body(Object data) =>
    jsonEncode({'code': 1, 'data': _envelope(jsonEncode(data))});

String _fixed(String plain) => base64Encode(
  SymmetricCrypto(
    'AES/CBC/PKCS5Padding',
    utf8.encode('Pxga!h*e4@T8xfOm'),
    ).setIv(utf8.encode(r'E&z!EHGLd$fli*8R')).encrypt(utf8.encode(plain)),
);
