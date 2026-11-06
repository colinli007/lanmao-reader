import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/js/source_js.dart';
import 'package:rule_engine/src/js/crypto.dart';
import 'package:rule_engine/src/js/codec.dart';
import 'package:rule_engine/src/request/analyze_url.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source([Map<String, Object?> extra = const {}]) => loadBookSources(
    jsonEncode({
      'bookSourceUrl': 'https://a.com',
      'bookSourceName': 'Java 类',
      ...extra,
    }),
  ).sources.single;

  String js(String code, {BookSource? s}) => (AnalyzeRule(
    SourceTask(env, s ?? source()),
  )..setContent('x')).getString('@js:$code');

  const md5 = 'Packages.java.security.MessageDigest.getInstance("MD5")';
  const string = 'Packages.java.lang.String';
  const hex =
      'function hex(b) { return b.map(function(x) { return (x & 255).toString(16).padStart(2,"0"); }).join(""); }';

  const responseClass = 'Packages.io.legado.app.help.http.StrResponse';

  test('ByteArrayOutputStream 低八位写入、范围复制、快照和 close/reset（JDK 对照）', () {
    expect(
      js('''
      var out = new Packages.java.io.ByteArrayOutputStream(0);
      out.write(-1); out.write(256); out.write(383);
      var input = [0,-128,127,0]; out.write(input,1,2); input[1] = 1;
      var snapshot = out.toByteArray(); snapshot[0] = 0;
      var first = out.toByteArray();
      try { out.write(input,3,2); } catch (e) {}
      var size = out.size();
      out.close(); out.write(65);
      var second = out.toByteArray();
      out.reset();
      JSON.stringify([first,size,second,out.size(),out.toByteArray()]);
    '''),
      '[[-1,0,127,-128,127],5,[-1,0,127,-128,127,65],0,[]]',
    );
  });

  test('字节流输出可交给编码与加密宿主，写入字节数组时复制输入', () {
    expect(
      js('''
      var out = Packages.java.io.ByteArrayOutputStream();
      var input = java.strToBytes("中文"); out.write(input); input[0] = 0;
      java.bytesToStr(out.toByteArray(), "UTF-8");
    '''),
      '中文',
    );
    expect(
      js('''
      var out = new Packages.java.io.ByteArrayOutputStream();
      out.write([97,98,99],3,0);
      out.write([97,98,99]);
      var cipher = java.createSymmetricCrypto("AES/ECB/PKCS5Padding", "1234567890123456");
      cipher.decryptStr(cipher.encrypt(out.toByteArray()));
    '''),
      'abc',
    );
  });

  test('字节流与列表无效容量/范围报错，不静默吞掉或留下部分写入', () {
    for (final name in ['io.ByteArrayOutputStream', 'util.ArrayList']) {
      for (final capacity in ['-1', '2147483648', 'NaN', 'null']) {
        expect(
          () => js('new Packages.java.$name($capacity)'),
          throwsA(isA<JsEvalException>()),
        );
      }
    }
    expect(
      js('''
      var out = new Packages.java.io.ByteArrayOutputStream(); out.write(65);
      var rejected = 0;
      for (var args of [[[1],-1,1], [[1],0,-1], [[1],0,2], [null], [[1,NaN]]]) {
        try { out.write.apply(out,args); } catch (e) { rejected++; }
      }
      JSON.stringify([rejected,out.toByteArray()]);
    '''),
      '[5,[65]]',
    );
  });

  test('ArrayList add/get、null、顺序、快照和 clear（JDK 对照）', () {
    expect(
      js('''
      var list = new Packages.java.util.ArrayList(0);
      var empty = list.isEmpty(), added = list.add(null);
      var value = {name:"甲"}; list.add(value); list.add(value);
      var copy = list.toArray(); copy[1] = "changed";
      var same = list.get(1) === value && list.get(2) === value;
      var size = list.size(), saved = list.toArray();
      var rejected = 0;
      for (var i of [-1,3]) { try { list.get(i); } catch (e) { rejected++; } }
      list.clear();
      JSON.stringify([empty,added,same,size,saved,list.size(),copy,rejected]);
    '''),
      '[true,true,true,3,[null,{"name":"甲"},{"name":"甲"}],0,[null,"changed",{"name":"甲"}],2]',
    );
  });

  test('缓存的流与列表跨任务可用，Java 包别名共享构造器', () {
    final s = source({
      'jsLib': '''
      var stream = new java.io.ByteArrayOutputStream();
      var list = new java.util.ArrayList();
      function append() { stream.write(65); list.add({name:"甲"}); return "ok"; }
      function take() { return JSON.stringify([stream.toByteArray(),list.toArray(),
        java.io.ByteArrayOutputStream === Packages.java.io.ByteArrayOutputStream,
        java.util.ArrayList === Packages.java.util.ArrayList]); }
    ''',
    });
    expect(js('append()', s: s), 'ok');
    expect(js('take()', s: s), '[[65],[{"name":"甲"}],true,true]');
  });

  test('格格党原始规则在四链路中解码 HTML5 实体（离线页面）', () {
    final s = loadBookSources(
      File('test/fixtures/ggd_java_source.json').readAsStringSync(),
    ).sources.single;
    env.respond('https://www.ggd66.com/search/?searchkey=test', '''
      <div class="bookbox"><div class="bookname"><a href="/qu/1/">江山&amp;NotEqualTilde;</a></div>
      <span class="author">作者：测试作者</span></div>
    ''');
    env.respond('https://www.ggd66.com/qu/1/', '''
      <meta property="og:novel:book_name" content="江山≂̸">
      <meta property="og:novel:author" content="测试作者">
      <div class="bookintro">简介 &copy;<br>站点宣传</div>
      <dl id="list-chapterAll"><dd><a href="/qu/1/100.html">第一章&amp;NotEqualTilde;</a></dd></dl>
    ''');
    env.respond('https://www.ggd66.com/qu/1/100.html', '''
      <div id="rtext"><p>正文&amp;NotEqualTilde;第一段。</p><p>第二段。</p></div>
    ''');
    final found = searchBooks(env, s, 'test').single;
    expect(found.name, '江山≂̸');
    final book = getBookInfo(env, s, found.toBook());
    expect(book.name, '江山≂̸');
    expect(book.intro, '简介 ©');
    final chapters = getChapterList(env, s, book);
    expect(chapters.single.title, '第一章≂̸');
    final content = getContent(env, s, book, chapters.single);
    expect(content.content, contains('正文≂̸第一段。'));
    expect(content.content, contains('第二段。'));
  });

  test('Parser Java 包入口只解实体，保留标签，按属性模式处理缺分号实体', () {
    final task = SourceTask(env, source());
    expect(
      SourceJs.instance.evalSource(task, '''
      org.jsoup.parser.Parser.unescapeEntities("<b>&amp; &NotEqualTilde; &copy=1</b>", false)
    '''),
      '<b>& ≂̸ ©=1</b>',
    );
    expect(
      SourceJs.instance.evalSource(task, '''
      Packages.org.jsoup.parser.Parser.unescapeEntities("&amp; &copy=1 &amp-1 &amp_1", true)
    '''),
      '& &copy=1 &amp-1 &amp_1',
    );
    expect(
      SourceJs.instance.evalSource(
        task,
        'org.jsoup.parser.Parser === Packages.org.jsoup.parser.Parser',
      ),
      true,
    );
    expect(
      () => js('org.jsoup.parser.Parser.unescapeEntities(null, true)'),
      throwsA(isA<JsEvalException>()),
    );
    expect(
      () => js('org.jsoup.parser.Parser.unescapeEntities("&amp;")'),
      throwsA(isA<JsEvalException>()),
    );
  });

  test('StrResponse 调用或 new 构造真实响应，body 可空，默认 200/OK 和空头', () {
    expect(
      js('''
      var r = $responseClass("https://a.com", "正文");
      JSON.stringify([r.url(), r.body(), r.code(), r.message(), r.isSuccessful(),
        r.raw().header("Set-Cookie"), r.headers(), r.cookies(), r.callTime(), r.request().url()]);
    '''),
      '["https://a.com/","正文",200,"OK",true,null,{},{},0,"https://a.com/"]',
    );
    expect(
      js('new $responseClass("https://a.com/x", null).body() === null'),
      'true',
    );
    expect(
      js('new $responseClass("not a URL", "body").url()'),
      'http://localhost/',
    );
    expect(
      js('$responseClass("HTTP://EXAMPLE.COM:80/a/../b?q=中文 空格", "").url()'),
      'http://example.com/b?q=%E4%B8%AD%E6%96%87%20%E7%A9%BA%E6%A0%BC',
    );
    for (final url in [
      '/relative',
      'ftp://a.com/x',
      'https://a.com:0/',
      'https://a.com:65536/',
    ]) {
      expect(
        js('$responseClass(${jsonEncode(url)}, "").url()'),
        'http://localhost/',
      );
    }
    expect(
      () => js('$responseClass(null, "x")'),
      throwsA(isA<JsEvalException>()),
    );
    expect(
      () => js('$responseClass("https://a.com")'),
      throwsA(isA<JsEvalException>()),
    );
  });

  test('原始点众/聚合 loginCheckJs 解密后返回响应，替换旧正文并供搜索链路解析', () {
    final fixtures =
        jsonDecode(
              File(
                'test/fixtures/response_java_sources.json',
              ).readAsStringSync(),
            )
            as List;
    const plain = '<li><a href="/book/1">测试小说</a></li>';
    for (final fixture in fixtures.cast<Map<String, Object?>>()) {
      final s = source({
        ...fixture,
        'searchUrl': '/search',
        'ruleSearch': {
          'bookList': 'tag.li',
          'name': 'tag.a@text',
          'bookUrl': 'tag.a@href',
        },
      });
      final encrypted = s.bookSourceName.contains('点众')
          ? jsonEncode({
              'data': hexEncode(
                SymmetricCrypto(
                      'AES/CBC/PKCS7Padding',
                      utf8.encode('dzkjgfyxgshylgzm'),
                    )
                    .setIv(utf8.encode('apiupdownedcrypt'))
                    .encrypt(utf8.encode(plain)),
              ),
            })
          : 'html_b="${base64Encode(utf8.encode(plain))}"';
      final url = '${s.bookSourceUrl}/search';
      env.respond(url, encrypted);
      final books = searchBooks(env, s, '测试');
      expect(books.single.name, '测试小说');
      expect(books.single.bookUrl, '${s.bookSourceUrl}/book/1');
    }
  });

  test('loginCheckJs 新响应的地址和正文生效，不保留旧响应头', () {
    final s = source({
      'searchUrl': '/search',
      'loginCheckJs':
          '''
        var r = new $responseClass("https://other.com/path/", "<li><a href='book'>新正文</a></li>");
        if (r.headers("Set-Cookie").length || r.header("X-Old") !== null) throw new Error("残留响应头");
        r;
      ''',
      'ruleSearch': {
        'bookList': 'tag.li',
        'name': 'tag.a@text',
        'bookUrl': 'tag.a@href',
      },
    });
    env.respond(
      'https://a.com/search',
      HttpResult(
        statusCode: 403,
        url: 'https://a.com/search',
        body: utf8.encode('旧正文'),
        headers: {'x-old': 'old'},
        setCookies: ['sid=old'],
      ),
    );
    final book = searchBooks(env, s, '测试').single;
    expect(book.name, '新正文');
    expect(book.bookUrl, 'https://other.com/path/book');
  });

  test('String 构造、默认 UTF-8、有符号字节与跨宿主传值', () {
    expect(
      js('JSON.stringify(new $string("中文").getBytes())'),
      '[-28,-72,-83,-26,-106,-121]',
    );
    expect(
      js('JSON.stringify($string("中文").getBytes("GBK"))'),
      '[-42,-48,-50,-60]',
    );
    expect(js('new $string([-28,-72,-83,-26,-106,-121], "UTF-8")'), '中文');
    expect(js('new $string([-42,-48,-50,-60], "GBK") + "!"'), '中文!');
    expect(js('new $string()'), '');
    expect(
      js('java.md5Encode(new $string("abc"))'),
      '900150983cd24fb0d6963f7d28e17f72',
    );
    expect(
      js('typeof "abc".getBytes + ":" + typeof java.md5Encode("abc").getBytes'),
      'undefined:undefined',
    );
  });

  test('String 不支持的构造参数和字符集明确报错', () {
    for (final expression in [
      'new $string(null)',
      'new $string([1], 0, 1)',
      'new $string([65], null)',
      'new $string("a").getBytes(null)',
      'new $string("a").getBytes("unknown-charset")',
    ]) {
      expect(() => js(expression), throwsA(isA<JsEvalException>()));
    }
  });

  test('MD5 分次 update、字节范围、复制输入、digest 后重置', () {
    expect(
      js('''
      $hex
      var md = $md5;
      md.update(97);
      var input = [0,98,99,0];
      md.update(input,1,2);
      input[1] = 100;
      hex(md.digest()) + ":" + hex(md.digest()) + ":" + md.getDigestLength();
    '''),
      '900150983cd24fb0d6963f7d28e17f72:d41d8cd98f00b204e9800998ecf8427e:16',
    );
  });

  test('digest(bytes) 追加已有状态，reset 丢弃已有状态', () {
    expect(
      js('''
      $hex
      var md = $md5;
      md.update([97]);
      var first = hex(md.digest([98,99]));
      md.update([120]); md.reset();
      first + ":" + hex(md.digest([97,98,99]));
    '''),
      '900150983cd24fb0d6963f7d28e17f72:900150983cd24fb0d6963f7d28e17f72',
    );
  });

  test('SHA-256 已知向量与独立实例', () {
    expect(
      js('''
      $hex
      var a = $md5, b = Packages.java.security.MessageDigest.getInstance("SHA-256");
      a.update([97]); b.update([97,98,99]);
      hex(a.digest()) + ":" + hex(b.digest());
    '''),
      '0cc175b9c0f1b6a831c399e269772661:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('不支持的摘要算法立即报错，非法范围不改变状态', () {
    expect(
      js(
        'try { Packages.java.security.MessageDigest.getInstance("unknown"); "bad" } catch (e) { "caught" }',
      ),
      'caught',
    );
    expect(
      js('''
      $hex
      var md = $md5; md.update([97]);
      try { md.update([98],0,2); } catch (e) {}
      try { md.digest([98],0,1); } catch (e) {}
      hex(md.digest([98,99]));
    '''),
      '900150983cd24fb0d6963f7d28e17f72',
    );
  });

  test('jsLib 词法 java 是包，规则/URL/书源 java 与 this.java 仍是宿主', () {
    final s = source({
      'jsLib':
          '''
      var JavaString = java.lang.String;
      function sign(s) {
        var md = java.security.MessageDigest.getInstance("MD5");
        md.update(new JavaString(s).getBytes("UTF-8"));
        $hex
        return hex(md.digest()) + ":" + this.java.md5Encode(s);
      }
    ''',
    });
    const expected =
        '900150983cd24fb0d6963f7d28e17f72:900150983cd24fb0d6963f7d28e17f72';
    expect(js('sign("abc")', s: s), expected);
    final task = SourceTask(env, s);
    expect(
      buildSourceRequest(task, '@js:"https://a.com/" + sign("abc")').http.url,
      'https://a.com/$expected',
    );
    expect(SourceJs.instance.evalSource(task, 'sign("abc")'), expected);
    expect(
      js('typeof java.lang + ":" + typeof java.security', s: s),
      'undefined:undefined',
    );
    expect(
      SourceJs.instance.evalSource(
        task,
        'java === source && typeof java.lang === "undefined"',
      ),
      true,
    );
  });

  test('jsLib 缓存的摘要对象可以跨任务累计与重置', () {
    final s = source({
      'jsLib':
          '''
      var savedDigest = java.security.MessageDigest.getInstance("MD5");
      function feed() { savedDigest.update([97]); return "ok"; }
      function finish() { $hex return hex(savedDigest.digest([98,99])); }
    ''',
    });
    expect(js('feed()', s: s), 'ok');
    expect(js('finish()', s: s), '900150983cd24fb0d6963f7d28e17f72');
  });

  test('酷狗原始 jsLib 生成非空且正确的搜索签名', () {
    final json =
        jsonDecode(
              File('test/fixtures/kugou_java_source.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    // 只冻结时钟，签名函数和搜索 URL 规则使用合集原文。
    json['jsLib'] = (json['jsLib']! as String).replaceAll(
      'new Date().getTime()',
      '1700000000000',
    );
    final s = loadBookSources(jsonEncode(json)).sources.single;
    final request = buildSourceRequest(
      SourceTask(env, s),
      s.searchUrl!,
      key: '三界红包群',
      page: 1,
    );
    final params = Uri.parse(request.http.url).queryParameters;
    expect(params['signature'], '7db586a991582aae0582b138affb2736');
    expect(params['clienttime'], '1700000000');
    expect(params['keyword'], '三界红包群');
    expect(request.http.headers['x-router'], 'complexsearch.kugou.com');
  });
}
