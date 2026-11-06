import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 链路里的 JS：source-request 的「登录检查 JS」、book-chains 的「目录的 formatJs」和字段错误
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source(Map<String, Object?> json) =>
      loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': '测试源', ...json})).sources.single;

  group('登录检查 JS', () {
    final search = {
      'searchUrl': '/s',
      'ruleSearch': {'bookList': 'tag.li', 'name': 'text', 'bookUrl': 'text'},
    };

    test('检查后带着改过的请求头重新请求', () {
      env.respond('https://a.com/s', <Object>['<p>请登录</p>', '<li>三体</li>']);
      final s = source({
        ...search,
        'loginCheckJs':
            "if (result.body().includes('请登录')) { java.headerMap.put('X-Token', 't1'); result = java.getStrResponse() } result",
      });
      expect(searchBooks(env, s, 'k').single.name, '三体');
      expect(env.requests.map((r) => r.headers['X-Token']), [null, 't1']);
    });

    test('返回了字符串', () {
      env.respond('https://a.com/s', '<li>三体</li>');
      final s = source({...search, 'loginCheckJs': 'result.body()'});
      expect(
        () => searchBooks(env, s, 'k'),
        throwsA(isA<JsEvalException>().having((e) => e.field, 'field', 'loginCheckJs').having((e) => e.sourceName, 's', '测试源')),
      );
    });

    test('result 是响应对象，java 是这次请求的 URL 上下文', () {
      env.respond('https://a.com/s', '<li>三体</li>');
      final s = source({...search, 'loginCheckJs': "java.put('u', result.url()); result"});
      expect(searchBooks(env, s, 'k').single.variables['u'], 'https://a.com/s');
    });
  });

  group('目录的 formatJs', () {
    BookSource toc(String formatJs) => source({
      'ruleToc': {'chapterList': 'tag.a', 'chapterName': 'text', 'chapterUrl': 'href', 'formatJs': formatJs},
    });
    Book book(BookSource s) => Book.of(s, 'https://a.com/b/1')..tocUrl = 'https://a.com/toc';

    test('给章节加序号', () {
      env.respond('https://a.com/toc', '<a href="1">序章</a><a href="2">第一章</a>');
      final s = toc("index + '. ' + title");
      expect(getChapterList(env, s, book(s)).map((c) => c.title), ['1. 序章', '2. 第一章']);
    });

    test('跨章节累积，未声明的变量也保留', () {
      env.respond('https://a.com/toc', '<a href="1">a</a><a href="2">b</a><a href="3">c</a>');
      final s = toc('gInt++; seen = (typeof seen === "undefined" ? "" : seen) + title; gInt + title + seen');
      expect(getChapterList(env, s, book(s)).map((c) => c.title), ['1aa', '2bab', '3cabc']);
    });

    test('返回 null 时章节名不变，单章出错只记日志，java 是全局包且没有 book', () {
      env.respond('https://a.com/toc', '<a href="1">a</a><a href="2">b</a><a href="3">c</a>');
      // MD3 BookChapterList 只注入 gInt/index/chapter/title；Rhino 顶层的 java 包仍然可见。
      final s = toc("if (index == 2) throw new Error('坏了'); index == 3 ? null : new java.lang.String(title) + typeof book");
      expect(getChapterList(env, s, book(s)).map((c) => c.title), ['aundefined', 'b', 'c']);
      expect(env.logs.single.message, contains('坏了'));
      expect(env.logs.single.field, 'ruleToc.formatJs');
    });
  });

  group('字段的 JS 错误', () {
    test('可选字段的 JS 错误被吞掉，必需字段的报错', () {
      env.respond('https://a.com/b/1', '<h1>三体</h1>');
      final s = source({
        'ruleBookInfo': {'name': 'tag.h1@text', 'intro': '@js:undefinedThing()', 'kind': '@js:java.t2s("x")'},
      });
      expect(
        () => getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')),
        throwsA(isA<UnsupportedHostApiException>().having((e) => e.field, 'field', 'ruleBookInfo.kind')),
      );
      final ok = source({'ruleBookInfo': {'name': 'tag.h1@text', 'intro': '@js:undefinedThing()'}});
      expect(getBookInfo(env, ok, Book.of(ok, 'https://a.com/b/1')).name, '三体');
      final bad = source({'ruleBookInfo': {'name': '@js:undefinedThing()'}});
      expect(
        () => getBookInfo(env, bad, Book.of(bad, 'https://a.com/b/1')),
        throwsA(isA<JsEvalException>().having((e) => e.field, 'field', 'ruleBookInfo.name')),
      );
    });

    test('内嵌 JS 表达式', () {
      env.respond('https://a.com/b/1', '<h1>三体</h1>');
      final s = source({'ruleBookInfo': {'name': 'tag.h1@text', 'intro': "{{'《' + book.name + '》'}}"}});
      expect(getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')).intro, '《三体》');
    });

    test('URL 里的 JS 错误指出字段', () {
      final s = source({'searchUrl': '@js:nope()', 'ruleSearch': {'bookList': 'tag.li'}});
      expect(
        () => searchBooks(env, s, 'k'),
        throwsA(isA<JsEvalException>().having((e) => e.field, 'field', 'searchUrl')),
      );
    });
  });
}
