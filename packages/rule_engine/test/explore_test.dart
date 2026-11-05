import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// book-chains「发现分类」「发现」的场景：回放环境，不连网
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source(Map<String, Object?> json) =>
      loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': '测试源', ...json})).sources.single;

  List<ExploreKind> kinds(String exploreUrl) => getExploreKinds(env, source({'exploreUrl': exploreUrl}));

  group('书源字段', () {
    test('exploreUrl、enabledExplore、ruleExplore', () {
      final s = source({
        'exploreUrl': '玄幻::/xh',
        'enabledExplore': false,
        'ruleExplore': {'bookList': 'class.item'},
      });
      expect(s.exploreUrl, '玄幻::/xh');
      expect(s.enabledExplore, isFalse);
      expect(s.ruleExplore['bookList'], 'class.item');
      expect(s.ruleExplore.field('name'), 'ruleExplore.name');
      // 缺少时 enabledExplore 为真
      expect(source({}).enabledExplore, isTrue);
    });
  });

  group('发现分类', () {
    test('JSON 数组：标题、地址、样式，没有地址的是小标题', () {
      final result = kinds(
        '[{"title":"玄幻","url":"/xh/{{page}}","style":{"layout_flexBasisPercent":0.25,"layout_flexGrow":1}},{"title":"排行"}]',
      );
      expect(result.map((k) => k.title), ['玄幻', '排行']);
      expect(result.first.url, '/xh/{{page}}');
      expect(result.first.type, ExploreKind.urlType);
      expect(result.first.style.basisPercent, 0.25);
      expect(result.first.style.grow, 1);
      expect(result.first.style.shrink, 1);
      expect(result.first.style.wrapBefore, isFalse);
      expect(result.last.url, isNull);
      expect(result.last.style.basisPercent, -1);
    });

    test('宽松 JSON：单引号、数字文本、布尔文本；不是对象的项跳过', () {
      final result = kinds(
        "[{title:'都市',url:'/ds',type:'url',style:{layout_flexGrow:'1',layout_flexBasisPercent:'0.4',layout_wrapBefore:'true'}},null,'x',]",
      );
      expect(result, hasLength(1));
      expect(result.single.style.grow, 1);
      expect(result.single.style.basisPercent, 0.4);
      expect(result.single.style.wrapBefore, isTrue);
    });

    test('交互式分类保留类型', () {
      expect(kinds('[{"title":"排序","type":"select","chars":["热门","最新"]}]').single.type, 'select');
    });

    test('文本：按 && 和换行拆开，每段是 标题::地址', () {
      final result = kinds('玄幻::/xh/{{page}}&&都市::/ds/{{page}}\n\n排行');
      expect(result.map((k) => (k.title, k.url)), [('玄幻', '/xh/{{page}}'), ('都市', '/ds/{{page}}'), ('排行', null)]);
    });

    test('@js: 生成，java 和 source 是书源对象', () {
      final result = kinds('@js:JSON.stringify([{title: source.bookSourceName, url: "/new"}])');
      expect(result.single.title, '测试源');
      expect(result.single.url, '/new');
    });

    test('<js></js> 生成文本形式', () {
      expect(kinds('<js>"最新::/new&&最热::/hot"</js>').map((k) => k.url), ['/new', '/hot']);
    });

    test('JS 出错时以错误结束', () {
      expect(() => kinds('@js:throw new Error("x")'), throwsA(isA<JsEvalException>()));
    });

    test('JSON 不合法时以错误结束', () {
      expect(() => kinds('[{"title":"x",]'), throwsA(isA<RuleException>()));
    });

    test('没有发现地址时没有分类', () {
      expect(getExploreKinds(env, source({})), isEmpty);
      expect(kinds('  '), isEmpty);
    });
  });

  group('发现', () {
    const page = '''
      <div class="item"><h3>三体</h3><a href="/b/1">x</a><p class="intro">科幻</p></div>
      <div class="item"><h3>球状闪电</h3><a href="/b/2">x</a></div>''';

    test('用 ruleExplore，页码代入分类地址', () {
      final s = source({
        'ruleSearch': {'bookList': 'class.none', 'name': 'tag.h3@text'},
        'ruleExplore': {'bookList': 'class.item', 'name': 'tag.h3@text', 'bookUrl': 'tag.a@href', 'intro': 'class.intro@text'},
      });
      env.respond('https://a.com/xh/2', page);
      final books = exploreBooks(env, s, '/xh/{{page}}', page: 2);
      expect(books.map((b) => b.name), ['三体', '球状闪电']);
      expect(books.first.bookUrl, 'https://a.com/b/1');
      expect(books.first.intro, '科幻');
      expect(books.first.origin, 'https://a.com');
    });

    test('ruleExplore 没有列表规则时用 ruleSearch', () {
      final s = source({
        'ruleSearch': {'bookList': 'class.item', 'name': 'tag.h3@text', 'bookUrl': 'tag.a@href'},
        'ruleExplore': {'name': 'tag.p@text'},
      });
      env.respond('https://a.com/xh', page);
      expect(exploreBooks(env, s, '/xh').map((b) => b.name), ['三体', '球状闪电']);
    });

    test('不判断 bookUrlPattern：地址匹配时也按列表解析', () {
      final s = source({
        'bookUrlPattern': r'https://a\.com/.*',
        'ruleSearch': {'bookList': 'class.item', 'name': 'tag.h3@text', 'bookUrl': 'tag.a@href'},
      });
      env.respond('https://a.com/xh', page);
      expect(exploreBooks(env, s, '/xh'), hasLength(2));
    });

    test('执行 loginCheckJs', () {
      final s = source({
        'loginCheckJs': 'java.log("checked"); result',
        'ruleSearch': {'bookList': 'class.item', 'name': 'tag.h3@text', 'bookUrl': 'tag.a@href'},
      });
      env.respond('https://a.com/xh', page);
      exploreBooks(env, s, '/xh');
      expect(env.logs.map((log) => log.message), contains('checked'));
    });
  });
}
