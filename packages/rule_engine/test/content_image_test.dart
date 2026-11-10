import 'dart:convert';
import 'dart:typed_data';

import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// book-chains「正文图片」的场景：回放环境，不连网
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source([Map<String, Object?> extra = const {}]) => testSource(extra);
  Book book(BookSource s) => Book.of(s, 'https://a.com/b/1');
  HttpResult image(String url, List<int> bytes, {int status = 200}) =>
      HttpResult(statusCode: status, url: url, body: Uint8List.fromList(bytes));

  test('带书源请求头，结果是响应的原始字节', () {
    final s = source({'header': '{"Referer":"https://a.com/"}'});
    env.respond('https://img.a.com/1.jpg', image('https://img.a.com/1.jpg', [0xFF, 0xD8, 0x00, 0x80]));
    expect(getContentImage(env, s, book(s), 'https://img.a.com/1.jpg'), [0xFF, 0xD8, 0x00, 0x80]);
    expect(env.requests.single.headers['Referer'], 'https://a.com/');
  });

  test('地址选项里的请求头也带上', () {
    final s = source();
    env.respond('https://img.a.com/2.jpg', image('https://img.a.com/2.jpg', [1, 2]));
    getContentImage(env, s, book(s), 'https://img.a.com/2.jpg,{"headers":{"X-Token":"t"}}');
    expect(env.requests.single.url, 'https://img.a.com/2.jpg');
    expect(env.requests.single.headers['X-Token'], 't');
  });

  test('imageDecode：book、result、src 都能用，返回的数组是图片的字节', () {
    final s = source({
      'ruleContent': {
        'imageDecode': '''
          var out = [];
          for (var i = 0; i < result.length; i++) out.push(result[i] ^ 1);
          if (src.indexOf('3.jpg') < 0 || book.bookUrl != 'https://a.com/b/1') throw 'bad';
          out''',
      },
    });
    env.respond('https://img.a.com/3.jpg', image('https://img.a.com/3.jpg', [0x10, 0xFF, 0x00]));
    expect(getContentImage(env, s, book(s), 'https://img.a.com/3.jpg'), [0x11, 0xFE, 0x01]);
  });

  test('imageDecode 返回 null 时以错误结束', () {
    final s = source({'ruleContent': {'imageDecode': 'null'}});
    env.respond('https://img.a.com/4.jpg', image('https://img.a.com/4.jpg', [1]));
    expect(() => getContentImage(env, s, book(s), 'https://img.a.com/4.jpg'), throwsA(isA<RuleException>()));
  });

  test('data 地址：不发请求，按 base64 解码', () {
    final s = source();
    final bytes = getContentImage(env, s, book(s), 'data:image/png;base64,iVBORw0KGgo=');
    expect(bytes, base64Decode('iVBORw0KGgo='));
    expect(bytes, hasLength(8));
    expect(env.requests, isEmpty);
  });

  test('data 地址按 Android Base64.DEFAULT 解码：空格跳过；不是 base64 的 data 地址以错误结束', () {
    final s = source();
    expect(getContentImage(env, s, book(s), 'data:image/png;base64,iVBO Rw0K Ggo='), base64Decode('iVBORw0KGgo='));
    expect(() => getContentImage(env, s, book(s), 'data:text/plain,abc'), throwsA(isA<RuleException>()));
    expect(env.requests, isEmpty);
  });

  test('404 时以错误结束', () {
    final s = source();
    env.respond('https://img.a.com/5.jpg', image('https://img.a.com/5.jpg', const [], status: 404));
    expect(
      () => getContentImage(env, s, book(s), 'https://img.a.com/5.jpg'),
      throwsA(isA<RuleException>().having((e) => e.message, 'message', contains('404'))),
    );
  });
}
