import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/js/source_js.dart';
import 'package:rule_engine/src/request/analyze_url.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:rule_engine/src/rule/rule_data.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// source-js 规格的场景：直接用引擎，不起 worker
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source([Map<String, Object?> extra = const {}]) => loadBookSources(
    jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': '测试源', ...extra}),
  ).sources.single;

  AnalyzeRule analyze(Object content, {RuleData? data, BookSource? s, ChapterData? chapter}) =>
      AnalyzeRule(SourceTask(env, s ?? source()), ruleData: data, chapter: chapter)
        ..setContent(content, baseUrl: 'https://a.com/b/1')
        ..setRedirectUrl('https://a.com/b/1');

  group('规则里的 JS 段', () {
    test('规则后接 JS', () {
      expect(analyze('<h1> 三体 </h1>').getString("tag.h1@text@js:result.trim() + '!'"), '三体!');
    });

    test('JS 代码里的内嵌规则', () {
      expect(analyze('{"id":7}').getString(r"@js:'/book/' + {{$.id}} * 2"), '/book/14');
    });

    test('JS 后面的替换', () {
      expect(analyze('a b').getString(r'@js:result##\s+##'), 'ab');
    });

    test('<js> 段和管道', () {
      expect(analyze('<h1>x</h1>').getString('<js>"<b>" + result.length + "</b>"</js>tag.b@text'), '10');
      expect(analyze('<h1>x</h1>').getString('tag.h1@text<js>result + 1</js><js>result + 2</js>'), 'x12');
    });

    test('@get 和 \$n 在 JS 代码里先替换', () {
      final data = ChainData()..variables['k'] = 'v';
      expect(analyze('<p></p>', data: data).getString("@js:'@get:{k}' + '!'"), 'v!');
    });
  });

  group('求值作用域', () {
    test('顶层变量不泄漏', () {
      final rule = analyze('x');
      expect(rule.getString('@js:var x = 1; leaked = 2; x'), '1');
      expect(rule.getString("@js:typeof x + ',' + typeof leaked"), 'undefined,undefined');
    });

    test('非严格模式', () {
      expect(analyze('x').getString('@js:for (i in [1,2]) {}; i'), '1');
    });

    test('顶层 this 是变量层', () {
      expect(analyze('abc').getString('@js:this.result + this.java.md5Encode16("a")'), 'abcc0f1b6a831c399e2');
    });
  });

  group('jsLib', () {
    test('jsLib 的函数和状态', () {
      final s = source({'jsLib': 'var n = 0; function inc() { return ++n; }'});
      final rule = analyze('x', s: s);
      expect(rule.getString('@js:inc()'), '1');
      expect(analyze('x', s: s).getString('@js:inc()'), '2');
    });

    test('通过 this 取调用方变量', () {
      final s = source({'jsLib': "function r() { return this.result + '!'; }"});
      expect(analyze('a', s: s).getString('@js:r()'), 'a!');
    });

    test('赋值只遮蔽', () {
      final s = source({'jsLib': 'var m = 5; function getM() { return m; }'});
      expect(analyze('a', s: s).getString('@js:m = 9; getM() + "," + m'), '5,9');
      expect(analyze('a', s: s).getString('@js:m'), '5');
    });

    test('JSON 形式不支持', () {
      final s = source({'jsLib': '{"a": "https://a.com/a.js"}'});
      expect(() => analyze('a', s: s).getString('@js:1'),
          throwsA(isA<NeedsJsException>().having((e) => e.message, 'message', '不支持的 jsLib 形式')));
    });

    test('jsLib 出错时每次求值都报同一错误', () {
      final s = source({'jsLib': 'throw new Error("坏了")'});
      for (var i = 0; i < 2; i++) {
        expect(() => analyze('a', s: s).getString('@js:1'),
            throwsA(isA<JsEvalException>().having((e) => e.message, 'message', contains('坏了'))));
      }
    });

    test('最多缓存 16 个，第 17 个淘汰最早的', () {
      // 第 i 个 jsLib 里的计数器：被淘汰后重新执行，计数从头开始
      BookSource lib(int i) => source({'jsLib': 'var c$i = 0; function inc$i() { return ++c$i; }'});
      expect(analyze('a', s: lib(0)).getString('@js:inc0()'), '1');
      for (var i = 1; i <= 16; i++) {
        analyze('a', s: lib(i)).getString('@js:inc$i()');
      }
      expect(analyze('a', s: lib(0)).getString('@js:inc0()'), '1');
      // 最近用过的还在
      expect(analyze('a', s: lib(16)).getString('@js:inc16()'), '2');
    });
  });

  group('注入变量', () {
    test('正文阶段的章节名', () {
      final chapter = BookChapter(bookUrl: 'https://a.com/b/1', baseUrl: 'https://a.com/b/1')..title = '第一章';
      final book = Book(bookUrl: 'https://a.com/b/1', origin: 'https://a.com', originName: '测试源');
      final rule = analyze('正文', data: book, chapter: chapter);
      expect(rule.getString(r"@js:title + '\n' + result"), '第一章\n正文');
      expect(rule.getString('@js:[typeof java, typeof cookie, typeof cache, src, baseUrl, chapter.title].join()'),
          'object,object,object,正文,https://a.com/b/1,第一章');
    });

    test('搜索列表阶段 book 是当前结果项', () {
      final item = SearchBook(bookUrl: '', origin: 'https://a.com', originName: '测试源')..name = '三体';
      expect(analyze('x', data: item).getString('@js:book.name'), '三体');
      expect(analyze('x').getString('@js:String(book) + typeof chapter'), 'nullobject');
    });

    test('URL 里没有 chapter', () {
      final task = SourceTask(env, source());
      expect(buildSourceRequest(task, '/c/{{typeof chapter}}/{{typeof title}}/{{typeof src}}', baseUrl: 'https://a.com').url,
          'https://a.com/c/undefined/undefined/undefined');
      expect(buildSourceRequest(task, '/s?k={{key}}&p={{page}}&b={{baseUrl}}', key: '三体', page: 2, baseUrl: 'https://a.com/x').url,
          'https://a.com/s?k=三体&p=2&b=https://a.com/x');
    });
  });

  group('书籍、章节和书源对象', () {
    test('修改书名写回书籍', () {
      final book = Book(bookUrl: 'https://a.com/b/1', origin: 'https://a.com', originName: '测试源')..name = '旧名';
      expect(analyze('简介', data: book).getString("@js:book.name = '新名'; result"), '简介');
      expect(book.name, '新名');
    });

    test('章节只读', () {
      final chapter = BookChapter(bookUrl: 'b', baseUrl: 'b')..title = '原名';
      expect(analyze('x', chapter: chapter).getString("@js:chapter.title = 'x'; chapter.title"), '原名');
      expect(chapter.title, '原名');
    });

    test('书源只读，字段来自书源 JSON', () {
      final s = source({'bookSourceComment': 'var shared = 1;'});
      expect(analyze('x', s: s).getString("@js:source.bookSourceName = 'x'; source.bookSourceName"), '测试源');
      expect(analyze('x', s: s).getString('@js:eval(String(source.bookSourceComment)); shared + 1'), '2');
    });
  });

  group('值转换', () {
    test('整数不带小数点，其余按 JS 的数字格式', () {
      final rule = analyze('x');
      expect(rule.getString('@js:1+1'), '2');
      expect(rule.getString('@js:1/2'), '0.5');
      expect(rule.getString('@js:12345678.5'), '12345678.5');
      expect(rule.getString('@js:1e21'), '1e+21');
      expect(rule.getString('@js:0/0'), 'NaN');
      expect(rule.getString('@js:null'), '');
      expect(rule.getString('@js:true'), 'true');
      expect(rule.getString('a{{1+1}}b{{null}}c'), 'a2bc');
    });

    test('数组按逗号连接，对象是 [object Object]', () {
      final rule = analyze('x');
      expect(rule.getString('@js:[1, "a", null, [2, 3]]'), '1,a,,2,3');
      expect(rule.getString('@js:({a: 1})'), '[object Object]');
    });

    test('字符串列表：文本按换行切开，数组直接作为列表，其他类型为空', () {
      final rule = analyze('x');
      expect(rule.getStringList(r'@js:"a\nb"'), ['a', 'b']);
      expect(rule.getStringList('@js:["a", 1]'), ['a', '1']);
      expect(rule.getStringList('@js:({a: 1})'), isNull);
      expect(rule.getStringList('@js:null'), isNull);
    });

    test('元素列表：数组是列表，null 是空列表，其他类型出错', () {
      final rule = analyze('x');
      expect(rule.getElements('@js:[1, 2]'), [1, 2]);
      expect(rule.getElements('@js:null'), isEmpty);
      expect(() => rule.getElements('@js:"a"'), throwsA(isA<JsEvalException>()));
    });

    test('JS 返回对象列表作为结果项', () {
      env.respond('https://a.com/s', 'x');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {'bookList': "@js:[{name:'三体',url:'/b/1',n:1.5},{name:'球状闪电',url:'/b/2'}]", 'name': 'name', 'bookUrl': 'url', 'author': 'n'},
      });
      final books = searchBooks(env, s, 'k');
      expect(books.map((b) => b.name), ['三体', '球状闪电']);
      expect(books.map((b) => b.bookUrl), ['https://a.com/b/1', 'https://a.com/b/2']);
      expect(books.first.author, '1.5');
    });

    test('JS 对象内容上的 JS、JSONPath 和模板', () {
      env.respond('https://a.com/s', 'x');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {
          'bookList': "@js:[{name:'三体',id:7}]",
          'name': r'$.name',
          'bookUrl': '/b/{{result.id}}',
          'author': '@js:result.name + result.id',
        },
      });
      final book = searchBooks(env, s, 'k').single;
      expect(book.name, '三体');
      expect(book.bookUrl, 'https://a.com/b/7');
      expect(book.author, '三体7');
    });
  });

  group('result 是元素或结构化值', () {
    test('result 是元素', () {
      env.respond('https://a.com/s', '<div class="item"><h3>三体</h3></div><div class="item"><h3>球状闪电</h3></div>');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {'bookList': 'class.item', 'name': "@js:result.select('h3').text()", 'bookUrl': 'tag.h3@text'},
      });
      expect(searchBooks(env, s, 'k').map((b) => b.name), ['三体', '球状闪电']);
    });

    test('result 是 JSON 对象', () {
      env.respond('https://a.com/s', '{"list":[{"name":"三体","author":"刘慈欣"}]}');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {'bookList': r'$.list[*]', 'name': r'$.name', 'author': "@js:result.author + '著'", 'bookUrl': r'$.name'},
      });
      expect(searchBooks(env, s, 'k').single.author, '刘慈欣著');
    });

    test('JSON 对象有 Java Map 的 toString 和 get', () {
      env.respond('https://a.com/s', '{"list":[{"id":23166,"name":"三体","s":1.0}]}');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {
          'bookList': r'$.list[*]',
          'name': r'$.name',
          'bookUrl': r"@js:'/b/' + String(result).match(/id=(\d+)/)[1]",
          'author': "@js:String(result) + '|' + result.get('name') + '|' + JSON.stringify(result)",
        },
      });
      final book = searchBooks(env, s, 'k').single;
      expect(book.bookUrl, 'https://a.com/b/23166');
      expect(book.author, '{id=23166, name=三体, s=1.0}|三体|{"id":23166,"name":"三体","s":1}');
    });

    test('正则分组是字符串数组，宿主列表有 Java 写法', () {
      final rule = analyze('a1b2');
      final items = rule.getElements(r':([a-z])(\d)');
      expect(rule.getString('@js:result.size() + result.get(1) + result.toArray().length + result.isEmpty()', content: items.first),
          '3a3false');
    });

    test('任务结束后句柄失效', () {
      final s = source({'jsLib': 'var saved = null; function keep(e) { if (e) saved = e; return saved; }'});
      final rule = analyze('<p>甲</p>', s: s);
      final p = rule.getElements('tag.p').single;
      expect(rule.getString('@js:keep(result).text()', content: p), '甲');
      // 同一个书源的下一个任务：jsLib 里留着上一个任务的元素
      expect(() => analyze('x', s: s).getString('@js:keep(null).text()'),
          throwsA(isA<JsEvalException>().having((e) => e.message, 'message', contains('对象已失效'))));
    });

    test('元素交回规则引擎后能继续用规则取值', () {
      final rule = analyze('<div><p class="t">甲</p><p class="t">乙</p></div>');
      final div = rule.getElements('tag.div').single;
      expect(rule.getString("<js>result.select('p').get(1)</js>text", content: div), '乙');
      expect(rule.getString("@js:result.select('p')", content: div), '<p class="t">甲</p>\n<p class="t">乙</p>');
    });
  });

  group('求值的错误与取消', () {
    test('JS 抛出的错误带消息', () {
      expect(() => analyze('x').getString('@js:throw new Error("坏了")'),
          throwsA(isA<JsEvalException>().having((e) => e.message, 'message', 'Error: 坏了')));
    });

    test('死循环被取消，try/catch 拦不住', () {
      // 求值开始前就设好取消标志：引擎在循环回边检查到中止
      env.cancel();
      expect(() => analyze('x').getString('@js:try { while (true) {} } catch (e) {}'), throwsA(isA<CancelledForTest>()));
    });

    test('嵌套求值超过 10 层时出错，try/catch 拦不住', () {
      // 每层都把下一层包在 try/catch 里
      const inner = 'try { java.getString(result) } catch (e) { "caught" }';
      final rule = analyze('@js:$inner');
      expect(() => rule.getString('@js:$inner'),
          throwsA(isA<JsEvalException>().having((e) => e.message, 'message', '嵌套求值超过 10 层')));
      // 10 层以内正常
      expect(rule.getString('@js:java.getString("@js:java.getString(\'@js:1+1\')")'), '2');
    });

    test('之后引擎仍可用', () {
      expect(analyze('x').getString('@js:40 + 2'), '42');
    });
  });

  group('Rhino 专有写法', () {
    test('使用 Packages：以「不支持的宿主 API：类名」结束，try/catch 拦不住', () {
      expect(() => analyze('x').getString('@js:try { Packages.java.lang.System.currentTimeMillis() } catch (e) { "caught" }'),
          throwsA(isA<UnsupportedHostApiException>().having((e) => e.api, 'api', 'Packages.java.lang.System.currentTimeMillis')));
      expect(() => analyze('x').getString('@js:new org.apache.commons.Foo()'),
          throwsA(isA<UnsupportedHostApiException>().having((e) => e.api, 'api', 'org.apache.commons.Foo')));
    });

    test('解构箭头函数：执行前加括号', () {
      expect(analyze('x').getString('@js:[["男频","1"],["女频","2"]].map([t,id]=>t+id).join(",")'), '男频1,女频2');
      expect(analyze('x').getString('@js:"[a]=>" + [1][0]'), '[a]=>1');
    });

    test('jsLib 里能用 Java 包对象：顶层、函数里、从 this 解构', () {
      final s = loadBookSources(jsonEncode({
        'bookSourceUrl': 'https://lib2.com',
        'bookSourceName': 'lib2',
        'jsLib': '''
          var J = Packages.org.jsoup.Jsoup;
          function first(html) { return org.jsoup.Jsoup.parse(html).select("p").first().text(); }
          function viaThis(html) { const { java, Packages } = this; return Packages.org.jsoup.Jsoup.parse(html).select("p").size() + java.md5Encode("a").length; }
        ''',
      })).sources.single;
      final rule = AnalyzeRule(SourceTask(env, s))..setContent('x');
      expect(rule.getString('@js:first("<p>甲</p><p>乙</p>") + J.parse("<p>丙</p>").text() + viaThis("<p>1</p>")'), '甲丙33');
    });

    test('jsLib 顶层调用不支持的 Java 类：以「不支持的宿主 API」结束', () {
      final s = loadBookSources(jsonEncode({
        'bookSourceUrl': 'https://lib3.com',
        'bookSourceName': 'lib3',
        'jsLib': 'var t = Packages.java.lang.System.currentTimeMillis();',
      })).sources.single;
      expect(() => (AnalyzeRule(SourceTask(env, s))..setContent('x')).getString('@js:t'),
          throwsA(isA<UnsupportedHostApiException>().having((e) => e.api, 'api', 'Packages.java.lang.System.currentTimeMillis')));
    });

    test('jsLib 里的解构箭头函数', () {
      final s = loadBookSources(jsonEncode({
        'bookSourceUrl': 'https://lib.com',
        'bookSourceName': 'lib',
        'jsLib': 'function pairs(list) { return list.map([a,b]=>a+b).join(","); }',
      })).sources.single;
      final rule = AnalyzeRule(SourceTask(env, s))..setContent('x');
      expect(rule.getString('@js:pairs([[1,2],[3,4]])'), '3,7');
    });

    test('宿主返回的是 JS 原生字符串', () {
      expect(analyze('x').getString("@js:typeof java.md5Encode('a') + (java.md5Encode('a') === '0cc175b9c0f1b6a831c399e269772661')"),
          'stringtrue');
    });
  });

  test('引擎在测试 isolate 里只有一个', () {
    expect(identical(SourceJs.instance, SourceJs.instance), isTrue);
  });
}
