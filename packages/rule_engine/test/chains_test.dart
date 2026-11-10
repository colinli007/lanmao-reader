import 'dart:convert';
import 'dart:typed_data';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/js/js_values.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// book-chains 规格的场景：回放环境，不起 isolate，不连网
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source(Map<String, Object?> json) =>
      loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': '测试源', ...json})).sources.single;

  HttpResult redirectedTo(String url, String body) =>
      HttpResult(statusCode: 200, url: url, body: Uint8List.fromList(utf8.encode(body)), redirected: true);

  group('搜索', () {
    final search = {
      'searchUrl': '/s?q={{key}}',
      'ruleSearch': {
        'bookList': 'class.item',
        'name': 'tag.h3@text',
        'author': 'class.author@text',
        'kind': 'class.tag@text',
        'wordCount': 'class.wc@text',
        'bookUrl': 'tag.a@href',
        'coverUrl': 'tag.img@src',
      },
    };

    test('正常搜索：书名为空的丢弃，地址转成绝对地址', () {
      env.respond('https://a.com/s?q=%E4%B8%89%E4%BD%93', '''
        <div class="item"><h3>三体 作者：刘慈欣</h3><p class="author">作者：刘慈欣</p><a href="/b/1">x</a>
          <span class="tag">科幻</span><span class="tag">完本</span><span class="wc">123456</span><img src="c.jpg"></div>
        <div class="item"><h3> </h3><a href="/b/2">x</a></div>
        <div class="item"><h3>球状闪电</h3><a href="/b/3">x</a><span class="wc">8000</span></div>''');
      final books = searchBooks(env, source(search), '三体');
      expect(books, hasLength(2));
      final first = books.first;
      expect(first.name, '三体');
      expect(first.author, '刘慈欣');
      expect(first.kind, '科幻,完本');
      expect(first.wordCount, '12.3万字');
      expect(first.bookUrl, 'https://a.com/b/1');
      expect(first.coverUrl, 'https://a.com/c.jpg');
      expect(books.last.wordCount, '8000字');
      expect(first.origin, 'https://a.com');
    });

    test('按书籍地址去重保留第一次，- 开头时整体倒序', () {
      env.respond('https://a.com/s?q=x', '''
        <div class="item"><h3>甲</h3><a href="/b/1">x</a></div>
        <div class="item"><h3>乙</h3><a href="/b/1">x</a></div>
        <div class="item"><h3>丙</h3><a href="/b/2">x</a></div>''');
      expect(searchBooks(env, source(search), 'x').map((b) => b.name), ['甲', '丙']);
      final reversed = {
        ...search,
        'ruleSearch': {...search['ruleSearch'] as Map, 'bookList': '-class.item'},
      };
      expect(searchBooks(env, source(reversed), 'x').map((b) => b.name), ['丙', '甲']);
    });

    test('搜索被重定向到详情页，详情链路不再请求', () {
      env.respond('https://a.com/s?q=x', redirectedTo('https://a.com/book/1.html', '<h1>三体</h1><p class="au">刘慈欣</p>'));
      final s = source({
        ...search,
        'bookUrlPattern': r'https://a\.com/book/\d+\.html',
        'ruleBookInfo': {'name': 'tag.h1@text', 'author': 'class.au@text'},
      });
      final books = searchBooks(env, s, 'x');
      expect(books, hasLength(1));
      expect(books.single.name, '三体');
      expect(books.single.bookUrl, 'https://a.com/book/1.html');
      final requests = env.requests.length;
      final book = getBookInfo(env, s, books.single.toBook());
      expect(book.author, '刘慈欣');
      expect(env.requests.length, requests);
    });

    test('列表为空且没有 bookUrlPattern 时按详情页解析', () {
      env.respond('https://a.com/s?q=x', '<h1>三体</h1>');
      final s = source({
        ...search,
        'ruleBookInfo': {'name': 'tag.h1@text'},
      });
      final books = searchBooks(env, s, 'x');
      expect(books.single.name, '三体');
      // 没有重定向：书籍地址是搜索地址
      expect(books.single.bookUrl, 'https://a.com/s?q=x');
    });

    test('列表为空但设置了 bookUrlPattern 且不匹配时返回空列表', () {
      env.respond('https://a.com/s?q=x', '<h1>三体</h1>');
      expect(searchBooks(env, source({...search, 'bookUrlPattern': 'nope'}), 'x'), isEmpty);
    });

    test('书名规则出错时整次搜索失败，可选字段出错时为空', () {
      env.respond('https://a.com/s?q=x', '<div class="item"><h3>甲</h3><a href="/1">x</a></div>');
      final badKind = {
        ...search,
        'ruleSearch': {...search['ruleSearch'] as Map, 'kind': '@css:p'},
      };
      expect(searchBooks(env, source(badKind), 'x').single.kind, isNull);
      final badName = {
        ...search,
        'ruleSearch': {...search['ruleSearch'] as Map, 'name': '@css:h3'},
      };
      expect(
        () => searchBooks(env, source(badName), 'x'),
        throwsA(isA<RuleException>().having((e) => e.field, 'field', 'ruleSearch.name').having((e) => e.sourceName, 'source', '测试源')),
      );
    });

    test('搜索地址为空', () {
      expect(() => searchBooks(env, source({}), 'x'), throwsA(isA<RuleException>()));
    });
  });

  group('分段搜索', () {
    final search = {
      'searchUrl': '/s?q={{key}}',
      'ruleSearch': {'bookList': 'tag.li', 'name': 'text', 'bookUrl': 'text'},
    };

    // 提交方的做法：第一段交回请求，自己发出，再把响应交给第二段
    List<SearchBook> twoSteps(BookSource s, String key) {
      final step = prepareSearch(env, s, key);
      return finishSearch(step, env.fetch(step.http));
    }

    RuleEngineException failure(List<SearchBook> Function() search) {
      try {
        search();
      } on RuleEngineException catch (e) {
        return e;
      }
      fail('没有出错');
    }

    test('地址里的 JS 只执行一次', () {
      env.respond('https://a.com/search?q=k', '<li>三体</li>');
      final s = source({...search, 'searchUrl': "@js:java.log('构造');'/search?q='+key"});
      expect(twoSteps(s, 'k').single.name, '三体');
      expect(env.logs.where((log) => log.message == '构造'), hasLength(1));
    });

    test('第二段执行 loginCheckJs', () {
      env.respond('https://a.com/s?q=k', <Object>['<p>请登录</p>', '<li>三体</li>']);
      final s = source({...search, 'loginCheckJs': "result.body().includes('请登录') ? java.getStrResponse() : result"});
      expect(twoSteps(s, 'k').single.name, '三体');
      expect(env.requests.map((r) => r.url), ['https://a.com/s?q=k', 'https://a.com/s?q=k']);
    });

    test('两段都能用书源对象：第一段登记过的对象随第一段失效，第二段重新登记', () {
      env.respond('https://a.com/s?q=13', '<li>X</li>');
      final s = source({...search, 'searchUrl': '/s?q={{source.getKey().length}},{"bodyJs":"result.replace(\'X\', source.getKey())"}'});
      expect(twoSteps(s, 'k').single.name, 'https://a.com');

      final handles = HandleTable();
      final id = handles.add(s);
      handles.clear();
      expect(() => handles.get<BookSource>(id), throwsA(isA<JsEvalException>()));
      final newId = handles.add(s);
      expect(newId, isNot(id));
      expect(handles.get<BookSource>(newId), same(s));
    });

    test('出错时的书源名和字段和一次执行相同', () {
      env.respond('https://a.com/s?q=k', '<li>三体</li>');
      final badName = source({
        ...search,
        'ruleSearch': {...search['ruleSearch'] as Map, 'name': '@css:h3'},
      });
      final badBodyJs = source({...search, 'searchUrl': '/s?q={{key}},{"bodyJs":"throw new Error(\'坏了\')"}'});
      for (final s in [badName, badBodyJs]) {
        final once = failure(() => searchBooks(env, s, 'k'));
        final split = failure(() => twoSteps(s, 'k'));
        expect(split.runtimeType, once.runtimeType);
        expect(split.toString(), once.toString());
        expect((split.sourceName, split.field), (once.sourceName, once.field));
      }
      expect(failure(() => twoSteps(badName, 'k')).field, 'ruleSearch.name');
      expect(failure(() => twoSteps(badBodyJs, 'k')).field, 'searchUrl');
    });
  });

  group('详情', () {
    test('type 选项的 data 地址：不发请求，正文是解码后字节的十六进制', () {
      final s = source({
        'ruleBookInfo': {'name': '@js:java.hexDecodeToString(result)'},
      });
      const url = 'data:;base64,5LiJ5L2T,{"type":"qingtian"}';
      final book = getBookInfo(env, s, Book.of(s, url));
      expect(env.requests, isEmpty);
      expect(book.name, '三体');
    });

    test('不带 type 的 data 地址照常交给网络', () {
      final s = source({'ruleBookInfo': {'name': 'tag.h1@text'}});
      getBookInfo(env, s, Book.of(s, 'data:;base64,5LiJ5L2T'));
      expect(env.requests.single.url, 'data:;base64,5LiJ5L2T');
    });

    test('目录就在详情页', () {
      env.respond('https://a.com/b/1', '<h1>三体</h1><ul><li><a href="1.html">第一章</a></li></ul>');
      final s = source({
        'ruleBookInfo': {'name': 'tag.h1@text'},
        'ruleToc': {'chapterList': 'tag.li', 'chapterName': 'tag.a@text', 'chapterUrl': 'tag.a@href'},
      });
      final book = getBookInfo(env, s, Book.of(s, 'https://a.com/b/1'));
      expect(book.tocUrl, 'https://a.com/b/1');
      final requests = env.requests.length;
      final chapters = getChapterList(env, s, book);
      expect(env.requests.length, requests);
      expect(chapters.single.title, '第一章');
    });

    test('init 用正则取不到时以错误结束', () {
      env.respond('https://a.com/b/1', '<p>x</p>');
      final s = source({
        'ruleBookInfo': {'init': r':<div class="info">(.*?)</div>', 'name': r'$1'},
      });
      expect(
        () => getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')),
        throwsA(isA<RuleException>().having((e) => e.field, 'field', 'ruleBookInfo.init')),
      );
    });

    test('init 用 JSoup 取不到时和 MD3 一样不报错，字段为空', () {
      env.respond('https://a.com/b/1', '<h1>三体</h1>');
      final s = source({
        'ruleBookInfo': {'init': 'class.book-info', 'name': 'tag.h1@text'},
      });
      expect(getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')).name, '');
    });

    test('init 取到的元素重新解析后取字段', () {
      env.respond('https://a.com/b/1', '<div class="info"><h1>三体</h1></div><h1>别的</h1>');
      final s = source({
        'ruleBookInfo': {'init': 'class.info', 'name': 'tag.h1@text'},
      });
      expect(getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')).name, '三体');
    });

    test('书名只在原来为空或 canReName 时覆盖，简介去掉标签', () {
      env.respond('https://a.com/b/1', '<h1>新名</h1><div id="i"><p>第一段</p><p>第二段</p></div><img src="/c.jpg">');
      final rules = {'name': 'tag.h1@text', 'intro': 'id.i@html', 'coverUrl': 'tag.img@src'};
      final keep = source({'ruleBookInfo': rules});
      final book = Book.of(keep, 'https://a.com/b/1')..name = '旧名';
      getBookInfo(env, keep, book);
      expect(book.name, '旧名');
      expect(book.intro, '　　第一段\n　　第二段');
      expect(book.coverUrl, 'https://a.com/c.jpg');
      final rename = source({
        'ruleBookInfo': {...rules, 'canReName': 'false'},
      });
      expect(getBookInfo(env, rename, Book.of(rename, 'https://a.com/b/1')..name = '旧名').name, '新名');
    });

    test('<usehtml> 开头的简介原样保留', () {
      env.respond('https://a.com/b/1', '<div id="i">&lt;usehtml&gt;&lt;b&gt;x&lt;/b&gt;&lt;/usehtml&gt;</div>');
      final s = source({
        'ruleBookInfo': {'intro': 'id.i@text'},
      });
      expect(getBookInfo(env, s, Book.of(s, 'https://a.com/b/1')).intro, '<usehtml><b>x</b></usehtml>');
    });
  });

  group('目录', () {
    BookSource toc([Map<String, Object?> extra = const {}]) => source({
      'ruleToc': {
        'chapterList': 'tag.li',
        'chapterName': 'tag.a@text||tag.b@text',
        'chapterUrl': 'tag.a@href',
        'isVolume': 'tag.b@data-v',
        ...extra,
      },
    });

    Book book(BookSource s, [String tocUrl = 'https://a.com/toc']) => Book.of(s, 'https://a.com/b/1')..tocUrl = tocUrl;

    test('卷与章节', () {
      env.respond('https://a.com/toc', '''<ul><li><b data-v="1">第一卷</b></li><li><a href="1.html">一</a></li>
        <li><a href="2.html">二</a></li><li><a href="3.html">三</a></li></ul>''');
      final chapters = getChapterList(env, toc(), book(toc()));
      expect(chapters, hasLength(4));
      expect(chapters.first.isVolume, isTrue);
      expect(chapters.first.url, '第一卷0');
      expect(chapters[1].url, '1.html');
      expect(chapterAbsoluteUrl(chapters[1]), 'https://a.com/1.html');
      expect(chapters.map((c) => c.index), [0, 1, 2, 3]);
    });

    test('空目录', () {
      env.respond('https://a.com/toc', '<p>没有</p>');
      expect(() => getChapterList(env, toc(), book(toc())), throwsA(isA<RuleException>().having((e) => e.message, 'message', '目录为空')));
    });

    test('按地址去重保留最后一次，- 开头时倒序', () {
      env.respond('https://a.com/toc', '<ul><li><a href="1">一</a></li><li><a href="2">二</a></li><li><a href="1">一（重复）</a></li></ul>');
      expect(getChapterList(env, toc(), book(toc())).map((c) => c.title), ['二', '一（重复）']);
      final reversed = source({
        'ruleToc': {'chapterList': '-tag.li', 'chapterName': 'tag.a@text', 'chapterUrl': 'tag.a@href'},
      });
      expect(getChapterList(env, reversed, book(reversed)).map((c) => c.title), ['二', '一']);
    });

    test('布尔字段', () {
      env.respond('https://a.com/toc', '<ul><li><a href="1" data-vip="NO">一</a></li><li><a href="2" data-vip="是">二</a></li></ul>');
      final s = toc({'isVip': 'tag.a@data-vip'});
      expect(getChapterList(env, s, book(s)).map((c) => c.isVip), [false, true]);
    });

    test('串行翻页防循环', () {
      final s = toc({'nextTocUrl': 'class.next@href'});
      env
        ..respond('https://a.com/toc', '<ul><li><a href="1">一</a></li></ul><a class="next" href="/toc2">下</a>')
        ..respond('https://a.com/toc2', '<ul><li><a href="2">二</a></li></ul><a class="next" href="/toc3">下</a>')
        ..respond('https://a.com/toc3', '<ul><li><a href="3">三</a></li></ul><a class="next" href="/toc">下</a>');
      expect(getChapterList(env, s, book(s)).map((c) => c.title), ['一', '二', '三']);
      expect(env.requests.map((r) => r.url), ['https://a.com/toc', 'https://a.com/toc2', 'https://a.com/toc3']);
    });

    test('首页列出全部分页时并发请求', () {
      final s = toc({'nextTocUrl': 'tag.option@value'});
      env.respond('https://a.com/toc', '''<ul><li><a href="0">首</a></li></ul><select>
        ${[for (var i = 1; i <= 4; i++) '<option value="/p$i">$i</option>'].join()}</select>''');
      for (var i = 1; i <= 4; i++) {
        env.respond('https://a.com/p$i', '<ul><li><a href="c$i">分页$i</a></li></ul>');
      }
      expect(getChapterList(env, s, book(s)).map((c) => c.title), ['首', '分页1', '分页2', '分页3', '分页4']);
    });

    test('JS 语法错误指出位置', () {
      env.respond('https://a.com/toc', '<ul><li><a href="1">一</a></li></ul>');
      final s = toc({'chapterName': 'tag.a@text@js:result.('});
      expect(
        () => getChapterList(env, s, book(s)),
        throwsA(
          isA<JsEvalException>()
              .having((e) => e.message, 'message', contains('SyntaxError'))
              .having((e) => e.sourceName, 'source', '测试源')
              .having((e) => e.field, 'field', 'ruleToc.chapterName'),
        ),
      );
    });
  });

  group('正文', () {
    BookSource content([Map<String, Object?> extra = const {}]) => source({
      'ruleContent': {'content': 'id.c@html', ...extra},
    });

    BookChapter chapter(String url, {String title = '第一章'}) =>
        BookChapter(bookUrl: 'https://a.com/b/1', baseUrl: 'https://a.com/b/')
          ..url = url
          ..title = title;

    Book book(BookSource s) => Book.of(s, 'https://a.com/b/1')..tocUrl = 'https://a.com/b/';

    test('格式化段落', () {
      env.respond('https://a.com/b/1.html', '<div id="c"><p>第一段</p><p>第二段&nbsp;</p><script>x</script></div>');
      final result = getContent(env, content(), book(content()), chapter('1.html'));
      expect(result.content, '　　第一段\n　　第二段');
    });

    test('保留图片并转成绝对地址，同时有多个地址属性时取写在后面的（MD3 的贪婪匹配）', () {
      env.respond('https://a.com/b/1.html', '<div id="c">文<img data-src="p.jpg" src="x.gif"><img src="/y.jpg,{&quot;a&quot;:1}"></div>');
      expect(
        getContent(env, content(), book(content()), chapter('1.html')).content,
        '　　文<img src="https://a.com/b/x.gif"><img src="https://a.com/y.jpg,{"a":1}">',
      );
    });

    test('净化广告行', () {
      env.respond('https://a.com/b/1.html', '<div id="c"><p>正文</p><p>请收藏本站</p></div>');
      final s = content({'replaceRegex': '##.*本站.*'});
      expect(getContent(env, s, book(s), chapter('1.html')).content, '　　正文\n　　');
    });

    test('正文为空', () {
      env.respond('https://a.com/b/1.html', '<div id="c"> </div>');
      expect(
        () => getContent(env, content(), book(content()), chapter('1.html')),
        throwsA(isA<RuleException>().having((e) => e.message, 'message', '正文为空')),
      );
    });

    test('正文规则为空时结果是章节地址', () {
      final s = source({});
      expect(getContent(env, s, book(s), chapter('1.html')).content, '1.html');
    });

    test('文件类书源', () {
      final s = source({'bookSourceType': 3, 'ruleContent': {'content': 'text'}});
      expect(() => getContent(env, s, book(s), chapter('1.html')), throwsA(isA<RuleException>().having((e) => e.message, 'message', '不支持的书源类型')));
    });

    test('正文分 3 页，第 3 页的链接指向下一章', () {
      final s = content({'nextContentUrl': 'class.next@href'});
      env
        ..respond('https://a.com/b/1.html', '<div id="c">一</div><a class="next" href="1_2.html">下</a>')
        ..respond('https://a.com/b/1_2.html', '<div id="c">二</div><a class="next" href="1_3.html">下</a>')
        ..respond('https://a.com/b/1_3.html', '<div id="c">三</div><a class="next" href="2.html">下</a>')
        ..respond('https://a.com/b/2.html', '<div id="c">下一章</div>');
      final result = getContent(env, s, book(s), chapter('1.html'), nextChapterUrl: 'https://a.com/b/2.html');
      expect(result.content, '　　一\n　　二\n　　三');
    });

    test('遇到下一章停止', () {
      final s = content({'nextContentUrl': 'class.next@href'});
      env
        ..respond('https://a.com/b/1.html', '<div id="c">一</div><a class="next" href="1_2.html">下</a>')
        ..respond('https://a.com/b/1_2.html', '<div id="c">二</div><a class="next" href="2.html">下</a>');
      final result = getContent(env, s, book(s), chapter('1.html'), nextChapterUrl: '2.html');
      expect(result.content, '　　一\n　　二');
      expect(env.requests.map((r) => r.url), ['https://a.com/b/1.html', 'https://a.com/b/1_2.html']);
    });

    test('正文页上取章节名', () {
      env.respond('https://a.com/b/1.html', '<h1>真正的标题</h1><div id="c">文</div>');
      final s = content({'title': 'tag.h1@text'});
      expect(getContent(env, s, book(s), chapter('1.html')).title, '真正的标题');
    });

    test('取消后不再请求', () {
      env.cancel();
      expect(() => getContent(env, content(), book(content()), chapter('1.html')), throwsA(isA<CancelledForTest>()));
      expect(env.requests, isEmpty);
    });
  });
}
