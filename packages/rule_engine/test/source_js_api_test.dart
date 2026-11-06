import 'dart:convert';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:rule_engine/src/request/analyze_url.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:rule_engine/src/rule/rule_data.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// source-js-api 规格的场景。不联网的用回放环境；网络、Cookie、跨 worker 的用本地 HTTP 服务和 worker 池。
void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source([Map<String, Object?> extra = const {}]) => loadBookSources(
    jsonEncode({'bookSourceUrl': 'https://www.a.com', 'bookSourceName': '测试源', ...extra}),
  ).sources.single;

  AnalyzeRule analyze(Object content, {RuleData? data, BookSource? s, ChapterData? chapter}) =>
      AnalyzeRule(SourceTask(env, s ?? source()), ruleData: data, chapter: chapter)
        ..setContent(content, baseUrl: 'https://www.a.com/b/1')
        ..setRedirectUrl('https://www.a.com/b/1');

  String js(String code, {Object content = 'x', BookSource? s}) => analyze(content, s: s).getString('@js:$code');

  group('三种 java 对象', () {
    test('URL 里调用回调规则', () {
      final task = SourceTask(env, source());
      expect(() => buildSourceRequest(task, "@js:java.getString('tag.a@text')"),
          throwsA(isA<JsEvalException>().having((e) => e.message, 'message', contains('TypeError'))));
    });

    test('书源 header 的 JS 里 java 就是书源', () {
      final s = source({'header': "@js:JSON.stringify({a: java.getKey(), b: java === source})"});
      final headers = buildSourceRequest(SourceTask(env, s), '/x').http.headers;
      expect(headers['a'], 'https://www.a.com');
      expect(headers['b'], 'true');
    });
  });

  group('不支持的宿主 API', () {
    const apis = [
      'startBrowser', 'startBrowserAwait', 'getVerificationCode', 'openUrl', 'webView', 'webViewGetSource',
      'webViewGetOverrideUrl', 'androidId', 'getReadBookConfig', 'getThemeMode', 'getThemeConfig',
      'downloadFile', 'cacheFile', 'importScript', 'getFile', 'readFile', 'readTxtFile', 'unzipFile', 'queryTTF',
      'replaceFont', 't2s', 's2t', 'createAsymmetricCrypto', 'createSign', 'refreshTocUrl', 'reGetBook', 'refreshExplore',
    ];
    for (final api in apis) {
      test('java.$api', () {
        expect(() => js('try { java.$api("x") } catch (e) { "caught" }'),
            throwsA(isA<UnsupportedHostApiException>().having((e) => e.api, 'api', 'java.$api')));
      });
    }

    test('调用验证码：正文链路以「不支持的宿主 API：java.getVerificationCode」结束', () {
      env.respond('https://www.a.com/c/1', '<p>x</p>');
      final s = source({'ruleContent': {'content': '@js:java.getVerificationCode(baseUrl)'}});
      final book = Book.of(s, 'https://www.a.com/b/1')..tocUrl = 'https://www.a.com/b/1';
      final chapter = BookChapter(bookUrl: book.bookUrl, baseUrl: book.tocUrl)
        ..url = '/c/1'
        ..title = '一';
      expect(
        () => getContent(env, s, book, chapter),
        throwsA(isA<UnsupportedHostApiException>().having(
          (e) => e.toString(),
          'toString',
          '不支持的宿主 API：java.getVerificationCode（测试源 ruleContent.content）',
        )),
      );
    });

    test('嵌套在回调规则里也拦不住', () {
      expect(() => js('try { java.getString("@js:try { java.t2s(1) } catch (e) {} ") } catch (e) { "caught" }'),
          throwsA(isA<UnsupportedHostApiException>()));
    });
  });

  group('变量读写', () {
    test('JS 写、规则读：详情 init 里 java.put，目录地址里 @get', () {
      env.respond('https://www.a.com/b/1', '<p>x</p>');
      env.respond('https://www.a.com/toc/9', '<a href="1">一</a>');
      final s = source({
        'ruleBookInfo': {'init': "@js:java.put('bid', '9'); result", 'name': 'tag.p@text', 'tocUrl': '/toc/@get:{bid}'},
        'ruleToc': {'chapterList': 'tag.a', 'chapterName': 'text', 'chapterUrl': 'href'},
      });
      final book = getBookInfo(env, s, Book.of(s, 'https://www.a.com/b/1'));
      expect(book.tocUrl, 'https://www.a.com/toc/9');
      expect(getChapterList(env, s, book).single.title, '一');
    });

    test('URL 里写变量后在列表里读', () {
      env.respond('https://www.a.com/s', '<li>1</li><li>2</li>');
      final s = source({
        'searchUrl': "@js:java.put('t', 'x'); '/s'",
        'ruleSearch': {'bookList': 'tag.li', 'name': '@get:{t}', 'bookUrl': 'text'},
      });
      expect(searchBooks(env, s, 'k').map((b) => b.name), ['x', 'x']);
    });

    test('put 返回写入的值，值为 null 时出错，三者都没有时规则 get 读书源级变量', () {
      final rule = analyze('x');
      expect(rule.getString("@js:java.put('a', 1) + java.get('a')"), '11');
      expect(() => rule.getString("@js:java.put('b', null)"), throwsA(isA<JsEvalException>()));
      expect(rule.getString("@js:source.put('sv', 'y'); java.get('sv')"), 'y');
    });

    test('URL 上下文的 put 只写章节或本次链路，get 不读书源级变量', () {
      final task = SourceTask(env, source());
      expect(buildSourceRequest(task, "/{{source.put('k', 'v'); java.get('k') + '|' + java.put('q', 'w')}}").url, '/|w');
    });

    test('source.put、source.get 在规则和 URL 里也读写书源级变量', () {
      final data = ChainData();
      expect(analyze('x', data: data).getString("@js:java.put('k', 'chain'); source.put('k', 'source')"), 'source');
      expect(analyze('x', data: data).getString("@js:java.get('k') + '|' + source.get('k')"), 'chain|source');
      buildSourceRequest(SourceTask(env, source()), "/{{source.put('u', 'v')}}");
      expect(js("source.get('u') + '|' + java.get('u')"), 'v|v');
      expect(() => js("source.put('n', null)"), throwsA(isA<JsEvalException>()));
    });

    test('@put/@get 和 java.put/java.get 是同一份数据', () {
      final data = ChainData();
      final rule = analyze('<b>v</b>', data: data);
      rule.getString('@put:{p:tag.b@text}tag.b@text');
      expect(rule.getString("@js:java.get('p')"), 'v');
      rule.getString("@js:java.put('q', 'w')");
      expect(rule.getString('@get:{q}'), 'w');
      expect(data.variables, {'p': 'v', 'q': 'w'});
    });
  });

  group('回调规则', () {
    test('回调用的是当前内容，不是 result', () {
      env.respond('https://www.a.com/s', '<li><a href="/b/1">三体</a><i>刘慈欣</i></li>');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {
          'bookList': 'tag.li',
          'name': 'tag.a@text',
          'author': "tag.i@text@js:java.getString('tag.a@text') + '/' + result",
          'bookUrl': 'tag.a@href',
        },
      });
      expect(searchBooks(env, s, 'k').single.author, '三体/刘慈欣');
    });

    test('getStringList 取不到时为 null，getElements 是元素列表，getElement 也是列表', () {
      final rule = analyze('<div class="d"><a href="/1">甲</a><a href="/2">乙</a></div>');
      expect(rule.getString("@js:String(java.getStringList('')) + java.getStringList('tag.x@text').length"), 'null0');
      expect(rule.getString("@js:java.getElements('.d a').toArray().map(a => a.text() + a.attr('href')).join(',')"),
          '甲/1,乙/2');
      expect(rule.getString("@js:java.getElement('.d a').size() + ',' + java.getElements('.x').length"), '2,0');
    });

    test('setContent 之后后续字段在新内容上取值', () {
      env.respond('https://www.a.com/b/1', '<h1>旧</h1>');
      final s = source({
        'ruleBookInfo': {'name': "@js:java.setContent('<h1>新</h1><i>作者</i>'); 'x'", 'author': 'tag.i@text', 'intro': 'tag.h1@text'},
      });
      final book = getBookInfo(env, s, Book.of(s, 'https://www.a.com/b/1'));
      expect(book.author, '作者');
      expect(book.intro, '新');
      expect(() => js('java.setContent(null)'), throwsA(isA<JsEvalException>()));
    });
  });

  group('Jsoup', () {
    const page = '<div class="d"><p>甲</p><script>var x = 1;</script><a href="/b/1">乙</a></div>';

    test('parse 之后选择、取文本和属性', () {
      expect(js('var doc = org.jsoup.Jsoup.parse(result); doc.select("a").first().text() + doc.select("a").attr("href")', content: page),
          '乙/b/1');
      expect(js('Packages.org.jsoup.Jsoup.parse(result).select("p").text()', content: page), '甲');
      expect(js('org.jsoup.Jsoup.parseBodyFragment("<p>丙</p>").select("body > p").text()'), '丙');
    });

    test('基准地址：abs: 转成绝对地址；没有基准地址时取不到相对地址', () {
      expect(js('org.jsoup.Jsoup.parse(\'<a href="/b/1">x</a>\', "https://a.com/s").select("a").attr("abs:href")'), 'https://a.com/b/1');
      expect(js('org.jsoup.Jsoup.parse(\'<a href="/b/1">x</a>\').select("a").attr("abs:href")'), '');
      expect(js('org.jsoup.Jsoup.parse(\'<a href="https://c.com/1">x</a>\').select("a").attr("abs:href")'), 'https://c.com/1');
    });

    test('data、remove', () {
      expect(js('var doc = org.jsoup.Jsoup.parse(result); doc.select("script").first().data()', content: page), 'var x = 1;');
      expect(js('var doc = org.jsoup.Jsoup.parse(result); doc.select("script").remove(); doc.select("div").text()', content: page),
          '甲 乙');
      expect(js('var doc = org.jsoup.Jsoup.parse(result); doc.select("a").first().remove(); doc.select("div").html().indexOf("乙")', content: page),
          '-1');
    });

    test('getAllElements 和按节点比较的 indexOf、lastIndexOf、includes、contains', () {
      const doc = 'var doc = org.jsoup.Jsoup.parse("<div><p>1</p><ol><li>a</li></ol><p>2</p></div>");';
      // 文档、html、head、body、div、p、ol、li、p：第一个 p 在第 5 位，ol 在第 6 位
      expect(js('$doc var all = doc.getAllElements(); [all.size(), all.indexOf(doc.select("p").first()), all.indexOf(doc.select("ol").first())].join("")'),
          '956');
      expect(js('$doc var ps = doc.select("p"); [ps.lastIndexOf(doc.select("p").last()), ps.includes(doc.select("p").first()), ps.contains(doc.select("li").first())].join("")'),
          '1truefalse');
      // 参数不是元素时按数组原来的方法
      expect(js('$doc doc.select("p").indexOf("x")'), '-1');
      // 白鹿书院的简介规则：只取 ol 之前的 p
      expect(js('''$doc var all = doc.getAllElements(); var olIdx = all.indexOf(doc.select("ol").first());
        var ps = doc.select("p"); var out = [];
        for (var j = 0; j < ps.size(); j++) { if (all.indexOf(ps.get(j)) < olIdx) out.push(ps.get(j).text()); }
        out.join()'''), '1');
    });

    test('元素列表的 remove(下标) 和 remove(元素) 是 Java 列表的写法', () {
      expect(js('var l = org.jsoup.Jsoup.parse("<p>1</p><p>2</p><p>3</p>").select("p"); var r = l.remove(0); r.text() + l.size() + l.text()'),
          '122 3');
      expect(js('var l = org.jsoup.Jsoup.parse("<p>1</p><p>2</p>").select("p"); var e = l.get(1); l.remove(e) + "" + l.size()'), 'true1');
    });
  });

  group('WebView 的 User-Agent', () {
    test('java 和 source 上都能取', () {
      expect(js('java.getWebViewUA()'), allOf(contains('; wv)'), contains('Mobile Safari')));
      expect(js('source.getWebViewUA() == java.getWebViewUA()'), 'true');
    });
  });

  group('元素包装对象', () {
    const html = '<div id="m" class="Box big"><p>一 <b>二</b></p><p data-x="1">三</p><span>  </span></div>';
    late AnalyzeRule rule;
    setUp(() => rule = analyze(html));
    String on(String code) => rule.getString('@js:var e = java.getElements("#m").get(0); $code');

    test('元素的方法', () {
      expect(on('e.text()'), '一 二 三');
      expect(on('e.select("p").get(0).ownText()'), '一');
      expect(on('e.select("p").get(0).html()'), '一 <b>二</b>');
      expect(on('e.select("b").get(0).outerHtml()'), '<b>二</b>');
      expect(on('[e.attr("id"), e.id(), e.hasAttr("ID"), e.hasClass("box"), e.tagName()].join("")'), 'mmtruetruediv');
      expect(on('e.selectFirst("p[data-x]").text() + e.children().size() + e.select("b").get(0).parent().tagName()'), '三3p');
      expect(on('e.selectFirst("x") === null'), 'true');
      expect(on('e.select("b").get(0).parentNode().tagName()'), 'p');
    });

    test('元素列表的方法', () {
      expect(on('var ps = e.select("p"); [ps.text(), ps.attr("data-x"), ps.eq(1).text(), ps.first().text(), ps.last().text()].join("|")'),
          '一 二 三|1|三|一 二|三');
      expect(on('e.select("p").html()'), '一 <b>二</b>\n三');
      expect(on('e.select("p").select("b").text() + e.select("p").length + e.select("p")[1].text()'), '二2三');
      expect(on('e.select("x").isEmpty() + "," + e.select("p").size()'), 'true,2');
      expect(on('[e.select("div,p").hasClass("BOX"), e.select("p").hasAttr("data-x"), e.select("p").hasClass("box")].join("")'),
          'truetruefalse');
      expect(on('JSON.stringify(e.select("p,span").eachText()) + JSON.stringify(e.select("p").eachAttr("data-x"))'),
          '["一 二","三"]["1"]');
    });
  });

  group('编码', () {
    test('宽松 Base64', () => expect(js(r"java.base64Decode('5LiJ5L2T\n')"), '三体'));

    test('encodeURI 是表单编码', () => expect(js("java.encodeURI('a b+三')"), 'a+b%2B%E4%B8%89'));

    test('严格 Base64 和 flags', () {
      expect(js("java.base64Encode('三体')"), '5LiJ5L2T');
      expect(js("java.base64Encode('三体', 0)"), '5LiJ5L2T\n');
      expect(js("java.base64Decode('-_-_', 8).length"), '3');
      expect(() => js("java.base64Decode('Y', 0)"), throwsA(isA<JsEvalException>()));
      expect(js("String(java.base64DecodeToByteArray(' '))"), 'null');
      expect(js("java.base64Decode('yP3M5Q==', 'GBK')"), '三体');
    });

    test('字节数组是 -128 到 127 的数组，能在 JS 和宿主之间往返', () {
      expect(js("java.strToBytes('三').join()"), '-28,-72,-119');
      expect(js("java.bytesToStr(java.strToBytes('三体', 'GBK'), 'GBK')"), '三体');
      expect(js("java.hexEncodeToString('三') + java.hexDecodeToString('e4b889') + java.hexDecodeToByteArray('ff')[0]"), 'e4b889三-1');
    });
  });

  group('摘要与加解密', () {
    test('AES 默认 ECB', () {
      final expected = base64EncodeStandard(SymmetricCrypto('AES/ECB/PKCS5Padding', utf8.encode('1234567890123456')).encrypt(utf8.encode('三体')));
      expect(js("java.createSymmetricCrypto('AES', '1234567890123456').encryptBase64('三体')"), expected);
    });

    test('旧函数的 bug 照旧', () {
      final cipher = js("java.createSymmetricCrypto('AES/CBC/PKCS5Padding', '1234567890123456', 'abcdefghijklmnop').encryptBase64('三体')");
      expect(js("java.aesEncodeToString('$cipher', '1234567890123456', 'AES/CBC/PKCS5Padding', 'abcdefghijklmnop')"), '三体');
    });

    test('加密器的方法', () {
      const create = "var c = java.createSymmetricCrypto('DESede/CBC/PKCS5Padding', '123456789012345678901234', 'abcdefgh');";
      expect(js('$create c.decryptStr(c.encryptHex("三体")) + c.decryptStr(c.encryptBase64("三体")) + c.decryptStr(c.encrypt("三体"))'),
          '三体三体三体');
      expect(js('$create c.setIv("hgfedcba") === c'), 'true');
      expect(() => js("java.createSymmetricCrypto('AES', 'short').encrypt('x')"), throwsA(isA<JsEvalException>()));
    });

    test('摘要和 HMAC', () {
      expect(js("java.md5Encode('a') + java.md5Encode16('a')"), '0cc175b9c0f1b6a831c399e269772661c0f1b6a831c399e2');
      expect(js("java.digestHex('a', 'SHA-1')"), hexEncode(digest('SHA-1', utf8.encode('a'))));
      expect(js("java.HMacHex('a', 'hmacsha256', 'k')"), hexEncode(hmac('HmacSHA256', utf8.encode('k'), utf8.encode('a'))));
    });
  });

  group('时间与文本', () {
    test('UTC 偏移按毫秒', () => expect(js("java.timeFormatUTC(0, 'yyyy-MM-dd HH:mm', 28800000)"), '1970-01-01 08:00'));

    test('中文章节号', () => expect(js("java.toNumChapter('正文 第一百零五章 风起')"), '第105章'));

    test('randomUUID、htmlFormat、timeFormat', () {
      expect(js('java.randomUUID().length'), '36');
      expect(js("java.htmlFormat('<p>a</p><p>b</p>')"), contains('a'));
      expect(js('java.timeFormat(0).length'), '16');
    });
  });

  group('日志与提示', () {
    test('log 可以写在表达式里', () {
      expect(analyze('abc').getString('@js:java.log(result.length)'), '3');
      expect(env.logs.single.message, '3');
      expect(env.logs.single.sourceUrl, 'https://www.a.com');
    });

    test('toast 降级为日志，带字段', () {
      env.respond('https://www.a.com/s', '<li>1</li>');
      final s = source({
        'searchUrl': '/s',
        'ruleSearch': {'bookList': 'tag.li', 'name': "@js:java.toast('提示'); java.longToast('长'); java.logType(1); 'x'", 'bookUrl': 'text'},
      });
      searchBooks(env, s, 'k');
      expect(env.logs.map((l) => l.message), ['提示', '长', 'java.lang.Double']);
      expect(env.logs.first.field, 'ruleSearch.name');
    });
  });

  group('Cookie 和缓存', () {
    test('cookie 读写与网络请求是同一份', () {
      env.cookieStore.setCookie('https://a.com', 'sid=1; x=2');
      expect(js("cookie.getCookie('https://m.a.com') + '|' + cookie.getKey('https://a.com', 'x') + '|' + java.getCookie('https://a.com', 'sid')"),
          'sid=1; x=2|2|1');
      js("cookie.replaceCookie('https://a.com', 'x=3; y=4')");
      expect(env.cookieStore.getCookie('https://a.com'), 'sid=1; x=3; y=4');
      js("cookie.removeCookie('https://www.a.com')");
      expect(env.cookieStore.getCookie('https://a.com'), '');
      expect(js("JSON.stringify(cookie.cookieToMap('a=1; b=; c=3')) + cookie.mapToCookie({a: 1, b: 'x'})"), '{"a":"1","c":"3"}a=1; b=x');
    });

    test('缓存：文本、过期、内存值', () {
      expect(js("cache.put('k', {a: 1}); cache.put('n', 2); cache.get('k') + cache.get('n') + String(cache.get('none'))"),
          '[object Object]2null');
      expect(js("cache.putMemory('m', {a: [1, 2]}); cache.getFromMemory('m').a[1]"), '2');
      expect(js("cache.putFile('f', 'v'); cache.getFile('f') + cache.get('f')"), 'vv');
      expect(js("cache.delete('f'); String(cache.getFile('f'))"), 'null');
    });
  });

  group('书源对象的方法', () {
    test('键、名字、自定义变量', () {
      expect(js("source.getKey() + source.getTag()"), 'https://www.a.com测试源');
      // Rhino 把 getKey()、getTag() 当成属性 key、tag，书源里常写 cookie.removeCookie(source.key)
      expect(js("source.key + source.tag"), 'https://www.a.com测试源');
      expect(js("source.key = 'x'; source.key"), 'https://www.a.com');
      expect(js("source.setVariable('v1'); source.getVariable()"), 'v1');
      expect(js("source.putVariable(null); source.getVariable()"), '');
    });

    test('登录头生效：之后该书源的请求带上它', () {
      final task = SourceTask(env, source());
      AnalyzeRule(task)
        ..setContent('x')
        ..getString(r"""@js:source.putLoginHeader('{"Authorization":"Bearer t"}')""");
      expect(buildSourceRequest(task, '/x').http.headers['Authorization'], 'Bearer t');
      expect(js("source.getLoginHeaderMap().Authorization"), 'Bearer t');
      expect(js('source.removeLoginHeader(); String(source.getLoginHeader())'), 'null');
    });

    test('登录信息：没有保存时按 loginUi 取默认值', () {
      final s = source({'loginUi': '[{"name":"账号","type":"text","default":"u"},{"name":"密码","type":"password"},{"name":"登录","type":"button"}]'});
      expect(js('JSON.stringify(source.getLoginInfoMap())', s: s), '{"账号":"u","密码":""}');
      expect(js('source.getLoginInfo()', s: s), '{"账号":"u","密码":""}');
      expect(js("source.putLoginInfo('{\"a\":\"b\"}') + JSON.stringify(source.getLoginInfoMap())", s: s), 'true{"a":"b"}');
      expect(js('source.removeLoginInfo(); String(source.getLoginInfo())', s: s), 'null');
    });
  });

  group('书籍和章节的方法', () {
    test('章节变量传到正文', () {
      env.respond('https://www.a.com/toc', '<a href="/c/1">一</a>');
      env.respond('https://www.a.com/c/1', '<p>正文</p>');
      final s = source({
        'ruleToc': {'chapterList': 'tag.a', 'chapterName': "@js:chapter.putVariable('cid', '42'); result.text()", 'chapterUrl': 'href'},
        'ruleContent': {'content': "@js:java.get('cid')"},
      });
      final book = Book.of(s, 'https://www.a.com/b/1')..tocUrl = 'https://www.a.com/toc';
      final chapter = getChapterList(env, s, book).single;
      expect(chapter.variables, {'cid': '42'});
      expect(getContent(env, s, book, chapter).content, '42');
    });

    test('书籍变量、目录倒序、自定义简介', () {
      env.respond('https://www.a.com/toc', '<a href="1">一</a><a href="2">二</a>');
      final s = source({
        'ruleToc': {'chapterList': "tag.a<js>book.setReverseToc(true); book.putVariable('k', 'v'); book.upCustomIntro(); result</js>", 'chapterName': 'text', 'chapterUrl': 'href'},
      });
      final book = Book.of(s, 'https://www.a.com/b/1')
        ..tocUrl = 'https://www.a.com/toc'
        ..intro = '简介';
      expect(getChapterList(env, s, book).map((c) => c.title), ['二', '一']);
      expect(book.variables['k'], 'v');
      expect(book.customIntro, '简介');
    });
  });

  group('网络（本地服务）', () {
    late HttpServer server;
    late String base;
    late RuleHost host;
    late WorkerPool pool;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/go':
            response
              ..statusCode = 302
              ..headers.set('location', '/book/1');
          case '/forbidden':
            response
              ..statusCode = 403
              ..write('no');
          case '/login':
            response.headers.add('set-cookie', 'sid=abc; Path=/');
            response.write('ok');
          case '/two-cookies':
            response.headers
              ..add('set-cookie', 'a=1; Path=/')
              ..add('set-cookie', 'b=2')
              ..set('x-one', 'v');
            response.write('ok');
          case '/slow':
            await Future<void>.delayed(const Duration(seconds: 10));
          case '/b64':
            response.write('5LiJ5L2T');
          default:
            final body = await utf8.decodeStream(request);
            response.write(jsonEncode({
              'method': request.method,
              'path': request.uri.path,
              'cookie': request.headers.value('cookie'),
              'auth': request.headers.value('authorization'),
              'sign': request.headers.value('x-sign'),
              'ua': request.headers.value('user-agent'),
              'body': body,
            }));
        }
        await response.close();
      });
      host = RuleHost();
      pool = WorkerPool(host.handle, size: 2);
    });

    tearDown(() async {
      pool.close();
      await server.close(force: true);
    });

    Future<String> run(String code, {Map<String, Object?> extra = const {}}) =>
        pool.run(_eval(jsonEncode({'bookSourceUrl': base, 'bookSourceName': '本地', ...extra}), code));

    test('请求失败不抛异常', () async {
      expect(await run("java.ajax('http://127.0.0.1:1/x').length > 0 && 'ok'"), 'ok');
    });

    test('ajax 带书源 Cookie，数组只用第一个，type 返回十六进制', () async {
      host.cookieStore.setCookie(base, 'sid=1');
      expect(jsonDecode(await run("java.ajax(['$base/echo', '$base/x'])"))['cookie'], 'sid=1');
      expect(jsonDecode(await run("java.ajax('$base/echo')"))['path'], '/echo');
      expect(await run("java.ajax('$base/b64,{\"type\":\"x\"}')"), hexEncode(utf8.encode('5LiJ5L2T')));
      expect(await run("java.ajax('$base/b64,{\"bodyJs\":\"java.base64Decode(result)\"}')"), '三体');
    });

    test('ajaxAll 按顺序返回响应对象', () async {
      expect(await run("java.ajaxAll(['$base/1', '$base/2']).map(r => JSON.parse(r.body()).path).join('')"), '/1/2');
    });

    test('connect 出错时返回伪造的 200，请求头参数整体替换书源请求头', () async {
      expect(await run("var r = java.connect('http://127.0.0.1:1/x'); r.code() + r.message()"), '200OK');
      final body = await run("java.connect('$base/e', '{\"Authorization\":\"a\"}').body()", extra: {'header': '{"X-S":"1"}'});
      expect(jsonDecode(body)['auth'], 'a');
    });

    test('拿到重定向地址；状态码 >= 400 报错；直连不带 Cookie', () async {
      expect(await run("java.get('$base/go', {}).header('Location')"), '/book/1');
      expect(await run("try { java.get('$base/forbidden', {}); 'no' } catch (e) { 'error' }"), 'error');
      host.cookieStore.setCookie(base, 'sid=1');
      final echo = jsonDecode(await run("java.post('$base/p', 'a=1', {}).body()"));
      expect(echo['cookie'], isNull);
      expect(echo['body'], 'a=1');
      expect(echo['method'], 'POST');
    });

    test('读响应头和 Cookie', () async {
      expect(await run("java.head('$base/login', {}).cookies().sid"), 'abc');
      expect(await run("var r = java.connect('$base/login'); [r.code(), r.isSuccessful(), r.headers()['set-cookie'] ? 1 : 0, r.raw().request().url() === r.url()].join('')"),
          '200true1true');
    });

    test('headers(名) 是这个响应头的全部值（OkHttp 的 Response.headers(name)）', () async {
      expect(await run("var r = java.connect('$base/two-cookies').raw(); [r.headers('Set-Cookie')[0], r.headers('set-cookie').length, r.headers('X-One').join(), r.headers('X-None').length].join('|')"),
          'a=1; Path=/|2|v|0');
    });

    test('js 选项改请求头', () async {
      final echo = jsonDecode(await run('''java.ajax("$base/s,{'js':\\"java.headerMap.put('X-Sign', java.md5Encode(result)); result\\"}")'''));
      expect(echo['sign'], hexEncode(digest('MD5', utf8.encode('$base/s'))));
    });

    test('JS 清掉 Cookie 后请求不再带', () async {
      host.cookieStore.setCookie(base, 'sid=1');
      expect(jsonDecode(await run("cookie.removeCookie('$base'); java.ajax('$base/e')"))['cookie'], isNull);
    });

    test('登录头生效', () async {
      final echo = jsonDecode(await run('''source.putLoginHeader('{"Authorization":"Bearer t"}'); java.ajax('$base/e')'''));
      expect(echo['auth'], 'Bearer t');
      // 另一个任务（可能在别的 worker 上）也带上
      expect(jsonDecode(await run("java.ajax('$base/e')"))['auth'], 'Bearer t');
    });

    test('不同 worker 读到同一份缓存', () async {
      await run("cache.put('k', 'v')");
      final reads = await Future.wait([run("cache.get('k')"), run("cache.get('k')"), run("cache.get('k')")]);
      expect(reads, ['v', 'v', 'v']);
    });

    test('阻塞在 ajax 里的 JS 被取消后 try/catch 拦不住', () async {
      final token = CancelToken();
      final future = pool.run(
        _eval(jsonEncode({'bookSourceUrl': base, 'bookSourceName': '本地'}), "try { java.ajax('$base/slow') } catch (e) { 'caught' }"),
        cancelToken: token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      token.cancel();
      await expectLater(future, throwsA(isA<TaskCancelledException>()));
      expect(await run('1 + 1'), '2');
    });
  });
}

/// 在 worker 里对书源求值一段规则 JS。
String Function() _eval(String sourceJson, String code) => () {
  final source = loadBookSources(sourceJson).sources.single;
  return (AnalyzeRule(SourceTask(const WorkerRuleEnvironment(), source))..setContent('x')).getString('@js:$code');
};
