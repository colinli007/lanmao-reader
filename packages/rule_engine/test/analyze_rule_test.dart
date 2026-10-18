import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:rule_engine/src/rule/rule_data.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// rule-syntax 规格的场景，行为对照 MD3 的 AnalyzeRule
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  AnalyzeRule analyze(Object content, {String? baseUrl, RuleData? data}) {
    final rule = AnalyzeRule(SourceTask(env, testSource()), ruleData: data)..setContent(content, baseUrl: baseUrl);
    if (baseUrl != null) rule.setRedirectUrl(baseUrl);
    return rule;
  }

  group('识别取值语法', () {
    test('JSON 内容上的无前缀规则按 JSONPath', () {
      expect(analyze('{"book":{"name":"三体"}}').getString('book.name'), '三体');
    });

    test('用 @@ 强制 JSoup', () {
      expect(analyze('["<b>x</b>"]').getString('@@tag.b@text'), 'x');
    });

    test('/ 开头按 XPath', () {
      expect(analyze('<h1> 标题 </h1>').getString('//h1/text()'), '标题');
    });

    test('JSON 内容上 / 开头也按 JSONPath', () {
      // JSONPath 解析不了 //a，结果为空
      expect(analyze('{"a":1}').getString('//a'), '');
    });

    test('@XPath: 和 @Json: 前缀', () {
      expect(analyze('<p>x</p>').getString('@XPath://p/text()'), 'x');
      expect(analyze('<p>{"a":1}</p>').getString(r'@Json:$.a'), '');
    });
  });

  group('JSoup 默认语法', () {
    test('class 名带空格：class 属性完全相同时匹配（jsoup 的 hasClass）', () {
      const html = '<ul class="float-list fill-block"><li>甲</li></ul><ul class="fill-block float-list"><li>乙</li></ul>';
      expect(analyze(html).getStringList('class.float-list fill-block@li@text'), ['甲']);
      expect(analyze(html).getStringList('class.fill-block@li@text'), ['甲', '乙']);
    });

    const list = '<div class="list"><a href="/1">一</a><a href="/2">二</a></div>';
    const items = '<ul><li>a</li><li>b</li><li>c</li></ul>';

    test('逐层选择并取文本', () {
      expect(analyze(list).getStringList('class.list@tag.a@text'), ['一', '二']);
    });

    test('负索引', () {
      expect(analyze(items).getString('tag.li.-1@text'), 'c');
    });

    test('区间索引倒序', () {
      expect(analyze(items).getStringList('tag.li[-1:0]@text'), ['c', 'b', 'a']);
    });

    test('排除索引', () {
      expect(analyze(items).getStringList('tag.li!0@text'), ['b', 'c']);
    });

    test('冒号列举多个索引', () {
      expect(analyze(items).getStringList('tag.li.0:2@text'), ['a', 'c']);
      expect(analyze(items).getStringList('tag.li[0,2]@text'), ['a', 'c']);
      expect(analyze(items).getStringList('tag.li[!0,2]@text'), ['b']);
    });

    test('区间省略两端、步长（research 第 4 节）', () {
      final rule = analyze(items);
      expect(rule.getStringList('tag.li[1:]@text'), ['b', 'c']);
      expect(rule.getStringList('tag.li[:1]@text'), ['a', 'b']);
      expect(rule.getStringList('tag.li[0:2:2]@text'), ['a', 'c']);
      expect(rule.getStringList('tag.li[-1:0:2]@text'), ['c', 'a']);
      // 两端在同一侧越界：整段跳过；单端越界：夹到边界
      expect(rule.getStringList('tag.li[5:9]@text'), isEmpty);
      expect(rule.getStringList('tag.li[1:9]@text'), ['b', 'c']);
    });

    test('旧式索引后面没有数字时以规则错误结束', () {
      expect(() => analyze(items).getString('tag.li.@text'), throwsA(isA<RuleException>()));
    });

    test('方括号里不是数字时当 CSS', () {
      expect(analyze('<a href="/1">x</a><a>y</a>').getStringList('a[href]@text'), ['x']);
    });

    test('索引越界时忽略', () {
      expect(analyze(items).getStringList('tag.li[5,1]@text'), ['b']);
    });

    test('html 取值去掉脚本和样式', () {
      final html = analyze('<div id="c"><p>正文</p><script>var a;</script><style>p{}</style></div>').getString('id.c@html');
      expect(html, '<div id="c">\n <p>正文</p>\n</div>');
    });

    test('属性跳过空白值并去重', () {
      expect(analyze('<a href="/1"></a><a href=" "></a><a href="/1"></a><a href="/2"></a>').getStringList('tag.a@href'), [
        '/1',
        '/2',
      ]);
    });

    test('text. 按自身文本选择，class 只看第一个名字', () {
      expect(analyze('<a>第一章</a><a>其它</a>').getString('text.第一@text'), '第一章');
      expect(analyze('<p class="a b">x</p>').getString('class.a.b@text'), 'x');
    });

    test('选择结果包含当前元素', () {
      final rule = analyze(list);
      final elements = rule.getElements('class.list');
      expect(rule.getString('class.list@tag.a.0@text', content: elements.single), '一');
    });

    test('多个结果取字符串时用换行连接', () {
      expect(analyze(list).getString('tag.a@text'), '一\n二');
    });
  });

  group('文本取值与 jsoup 一致', () {
    test('合并空白', () {
      expect(analyze('<p>  第一章\n   开始 </p>').getString('tag.p@text'), '第一章 开始');
    });

    test('ownText 不含子元素文本', () {
      expect(analyze('<p>作者：<a>刘慈欣</a></p>').getString('tag.p@ownText'), '作者：');
    });

    test('textNodes 去掉空白项并用换行连接', () {
      expect(analyze('<div> 一 <br> 二 <b>x</b> </div>').getString('tag.div@textNodes'), '一\n二');
    });
  });

  group('CSS 选择器', () {
    test('CSS 取属性', () {
      expect(analyze('<div class="cover"><img src="/a.jpg"></div>').getString('@css:div.cover > img@src'), '/a.jpg');
    });

    test('取字符串时没有 @ 以规则错误结束', () {
      expect(() => analyze('<p>x</p>').getString('@css:p'), throwsA(isA<RuleException>()));
    });

    test('取元素时整条是选择器', () {
      expect(analyze('<p>x</p><p>y</p>').getElements('@css:p'), hasLength(2));
    });
  });

  group('JSONPath', () {
    test('规则末尾的 {\$.x} 取不到值时不越界', () {
      // 取不到值时跳过 {\$. 的位置会超出末尾，MD3 里 Java 的 indexOf 返回 -1
      expect(analyze('{"id":1}').getString(r'/b/{$.nope}'), '');
    });

    test('数组结果用换行连接', () {
      expect(analyze('{"tags":["玄幻","完本"]}').getString(r'$.tags[*]'), '玄幻\n完本');
    });

    test('内嵌路径拼接', () {
      expect(analyze('{"id":42}').getString(r'/book/{$.id}.html'), '/book/42.html');
    });

    test('路径不存在', () {
      expect(analyze('{"a":1}').getString(r'$.missing'), '');
    });

    test('对象转字符串', () {
      expect(analyze('{"book":{"id":1,"name":"三体"}}').getString(r'$.book'), '{id=1, name=三体}');
    });

    test('取列表时结果不是数组则为空', () {
      expect(analyze('{"a":1}').getElements(r'$.a'), isEmpty);
      expect(analyze('{"list":[{"n":1},{"n":2}]}').getElements(r'$.list'), hasLength(2));
    });

    test('列表项作为内容继续取值', () {
      final rule = analyze('{"list":[{"name":"甲"},{"name":"乙"}]}');
      final names = [for (final item in rule.getElements(r'$.list')) rule.getString('name', content: item)];
      expect(names, ['甲', '乙']);
    });
  });

  group('XPath', () {
    test('取 meta 属性', () {
      expect(analyze('<meta property="og:title" content="三体">').getString("//meta[@property='og:title']/@content"), '三体');
    });

    test('谓词组合', () {
      const html = '<div class="desc" itemprop="description">要的</div><div class="desc">不要</div>';
      expect(analyze(html).getString("//div[@class='desc' and @itemprop='description']/text()"), '要的');
    });

    test('不支持的语法', () {
      expect(
        () => analyze('<a>x</a>').getString("//a[translate(.,'a','b')]"),
        throwsA(isA<RuleException>().having((e) => e.message, 'message', contains('不支持的 XPath'))),
      );
    });
  });

  group('组合运算符', () {
    test('|| 取第一个非空', () {
      expect(analyze('<p class="b">B</p>').getString('class.a@text||class.b@text'), 'B');
    });

    test('&& 合并', () {
      expect(analyze('<p class="a">A</p><p class="b">B</p>').getStringList('class.a@text&&class.b@text'), ['A', 'B']);
    });

    test('%% 交错合并', () {
      const html = '<h3>A1</h3><h3>A2</h3><p>B1</p><p>B2</p><p>B3</p>';
      expect(analyze(html).getStringList('tag.h3@text%%tag.p@text'), ['A1', 'B1', 'A2', 'B2']);
    });

    test('括号里的运算符不切分', () {
      expect(analyze('{"list":[{"a":1,"b":1,"name":"x"},{"a":1,"name":"y"}]}').getString(r'$.list[?(@.a && @.b)].name'), 'x');
    });

    test('括号不配对时以规则错误结束', () {
      expect(() => analyze('<a>x</a>').getString('tag.a[1&&tag.b'), throwsA(isA<RuleException>()));
    });
  });

  group('正则净化', () {
    test('删除广告', () {
      expect(analyze('<div id="content">正文。请记住本站域名</div>').getString('id.content@text##请记住本站.*'), '正文。');
    });

    test('只取第一个匹配', () {
      expect(analyze('共 12章 / 34章').getString(r'text##(\d+)章##第$1章###'), '第12章');
    });

    test('非法正则退化为字面量', () {
      expect(analyze('a[未闭合b').getString('text##[未闭合'), 'ab');
    });

    test('取列表时逐项替换', () {
      expect(analyze('<a>第1章</a><a>第2章</a>').getStringList(r'tag.a@text##第|章'), ['1', '2']);
    });

    test('## 前面为空时直接替换内容', () {
      expect(analyze('axb').getString('##x##y'), 'ayb');
    });
  });

  group('AllInOne 正则', () {
    test('正则列表与分组引用', () {
      final rule = analyze('<a href="/1">一</a><a href="/2">二</a>');
      final items = rule.getElements(r':<a href="(.*?)">(.*?)</a>');
      expect(items, hasLength(2));
      expect([for (final item in items) rule.getString(r'$2', content: item)], ['一', '二']);
      expect([for (final item in items) rule.getString(r'$1', content: item)], ['/1', '/2']);
    });

    test('分级：前一级的匹配拼接后作为下一级的输入', () {
      final rule = analyze('<ul><li>a1</li></ul><ol><li>b1</li></ol><ul><li>a2</li></ul>');
      final items = rule.getElements(r':<ul>.*?</ul>&&<li>(.*?)</li>');
      expect([for (final item in items) rule.getString(r'$1', content: item)], ['a1', 'a2']);
    });
  });

  group('变量与内嵌规则', () {
    test('详情页保存、目录页读取', () {
      final data = ChainData();
      final detail = analyze('{"id":"77","name":"三体"}', data: data);
      expect(detail.getString(r'$.name@put:{bid:$.id}'), '三体');
      final toc = analyze('<html></html>', data: data);
      expect(toc.getString('/toc/@get:{bid}'), '/toc/77');
    });

    test('内嵌规则拼接', () {
      expect(analyze('{"title":"三体","author":"刘慈欣"}').getString(r'{{$.title}} 作者 {{$.author}}'), '三体 作者 刘慈欣');
    });

    test('baseUrl 和 title', () {
      expect(analyze('<p></p>', baseUrl: 'https://a.com/b').getString('{{baseUrl}}?x'), 'https://a.com/b?x');
    });

    test('取不到的变量为空串', () {
      expect(analyze('<p></p>').getString('a@get:{nothing}b'), 'ab');
    });
  });

  group('需要 WebView 时明确报错', () {
    test('规则里有 @webjs:', () {
      expect(
        () => analyze('<p></p>').getString('@webjs:document.body.innerText'),
        throwsA(isA<NeedsWebViewException>().having((e) => e.snippet, 'snippet', '@webjs:document.body.innerText')),
      );
    });
  });

  group('地址取值', () {
    test('相对地址', () {
      expect(analyze('<a href="../2/">x</a>', baseUrl: 'https://a.com/book/1/').getString('tag.a@href', isUrl: true), 'https://a.com/book/2/');
    });

    test('不编码中文', () {
      expect(analyze('<a href="/search?k=三体">x</a>', baseUrl: 'https://a.com/s').getString('tag.a@href', isUrl: true), 'https://a.com/search?k=三体');
    });

    test('按重定向后的地址拼接', () {
      final rule = analyze('<a href="2.html">x</a>', baseUrl: 'https://a.com/b?id=1')..setRedirectUrl('https://m.a.com/book/1/');
      expect(rule.getString('tag.a@href', isUrl: true), 'https://m.a.com/book/1/2.html');
    });

    test('取到空白时为当前页面地址', () {
      expect(analyze('<a href=" ">x</a>', baseUrl: 'https://a.com/x').getString('tag.b@href', isUrl: true), 'https://a.com/x');
    });

    test('JSoup 取单个地址时只取第一个', () {
      expect(analyze('<a href="/1">x</a><a href="/2">y</a>', baseUrl: 'https://a.com/').getString('tag.a@href', isUrl: true), 'https://a.com/1');
    });

    test('取地址列表时去空去重', () {
      const html = '<a href="/1">x</a><a href="/1">y</a><a href="javascript:void(0)">z</a><a href="/2">w</a>';
      expect(analyze(html, baseUrl: 'https://a.com/').getStringList('tag.a@href', isUrl: true), ['https://a.com/1', 'https://a.com/2']);
    });
  });
}
