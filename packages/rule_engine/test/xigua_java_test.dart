import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 合集 1329 西瓜小说原始目录和正文规则（包含书源自带固定签名 key）。
// xigua_rsa_vectors.json 由本机 JDK KeyFactory/Signature 独立生成，
// 不通过被测引擎签名，也不需要联网或在测试时安装 JDK。
void main() {
  late FakeEnvironment env;
  late BookSource source;
  late Map<String, dynamic> vectors;
  late String keyBytes;
  setUp(() {
    env = FakeEnvironment();
    source = loadBookSources(
      File('test/fixtures/xigua_java_source.json').readAsStringSync(),
    ).sources.single;
    vectors =
        jsonDecode(
              File('test/fixtures/xigua_rsa_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    keyBytes = RegExp(
      r'jmkey=(\[[^\]]*\])',
    ).firstMatch(source.ruleContent['content']!)!.group(1)!;
  });
  tearDown(() => env.dispose());

  String js(String code, {BookSource? s}) => (AnalyzeRule(
    SourceTask(env, s ?? source),
  )..setContent('正文')).getString('@js:$code');

  String expected(String name) => base64Decode(
    vectors[name]['signature'] as String,
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String setup() =>
      '''
    var Spec = Packages.java.security.spec.PKCS8EncodedKeySpec;
    var Factory = Packages.java.security.KeyFactory;
    var Signature = Packages.java.security.Signature;
    var rawKey = $keyBytes;
    var spec = new Spec(rawKey);
    var key = Factory.getInstance('RSA').generatePrivate(spec);
    function hex(bytes) { return bytes.map(x => (x & 255).toString(16).padStart(2,'0')).join(''); }
  ''';

  test('西瓜原始目录和正文规则签名请求并读取 CDN 正文', () {
    const tocUrl = 'https://xigua.test/toc/1234';
    const contentUrl = 'https://xgmf.zuanqianyi.com/glory/free/1152?a';
    const cdnUrl = 'https://cdn.xigua.test/1234/5678.txt';
    env.respond(
      tocUrl,
      jsonEncode({
        'data': {
          'bookId': 1234,
          'chapterIdList': [5678],
          'chapterNameList': ['第一章 西瓜'],
        },
      }),
    );
    env.respond(contentUrl, [
      '{}',
      jsonEncode({
        'data': {
          'cdnUrls': [cdnUrl],
        },
      }),
    ]);
    env.respond(cdnUrl, '西瓜正文🚀。\n第二段中文。');
    final book = Book.of(source, 'https://xigua.test/book/1234')
      ..tocUrl = tocUrl;
    final chapter = getChapterList(env, source, book).single;
    expect(chapter.title, '第一章 西瓜');
    final content = getContent(env, source, book, chapter);
    // 原规则在正文前补换行，formatter 因而也缩进首段。
    expect(content.content, '　　西瓜正文🚀。\n　　第二段中文。');
    expect(content.title, '第一章 西瓜');
    expect(env.requests.map((r) => r.url), [
      tocUrl,
      contentUrl,
      contentUrl,
      cdnUrl,
    ]);
    final signedRequest = env.requests[2];
    expect(signedRequest.method, 'POST');
    expect(signedRequest.body, '{"chapterId":5678,"bookId":1234}');
    expect(signedRequest.headers['signtype'], '2');
    expect(signedRequest.headers['sign'], vectors['request']['signature']);
    expect(signedRequest.headers['pname'], 'com.dzmf.zmfxsdq');
  });

  test('西瓜使用的 UTF_8 别名在 Java String 中保留中文和补充平面字符', () {
    expect(
      js('''
      var JString = Packages.java.lang.String;
      var bytes = JString('中文🚀𠮷').getBytes('UTF_8');
      JSON.stringify([bytes, new JString(bytes,'UTF_8').toString()]);
    '''),
      jsonEncode([
        utf8.encode('中文🚀𠮷').map((b) => b.toSigned(8)).toList(),
        '中文🚀𠮷',
      ]),
    );
  });

  test('PKCS8EncodedKeySpec 和 RSA PrivateKey 对字节输入及 getter 做防御复制', () {
    expect(
      js('''
      ${setup()}
      var original = hex(rawKey);
      rawKey.fill(0); spec.getEncoded().fill(0); key.getEncoded().fill(0);
      var fromSpec = Factory.getInstance('RSA').generatePrivate(spec);
      JSON.stringify([hex(spec.getEncoded()) === original,
        hex(key.getEncoded()) === original, hex(fromSpec.getEncoded()) === original,
        spec.getFormat(),key.getAlgorithm(),key.getFormat()]);
    '''),
      '[true,true,true,"PKCS#8","RSA","PKCS#8"]',
    );
  });

  test('Signature update 的 byte、bytes 和 offset/length 拼接与 JDK 一致，sign 后重置', () {
    expect(
      js('''
      ${setup()}
      var signature = Signature.getInstance('SHA256WithRSA');
      signature.initSign(key);
      var message = java.strToBytes('中文🚀');
      signature.update(message[0]);
      signature.update(message,1,2);
      signature.update(message.slice(3));
      var first = hex(signature.sign()), empty = hex(signature.sign());
      signature.update(message);
      var repeated = hex(signature.sign());
      signature.update([1,2,3]); signature.initSign(key); signature.update(message);
      JSON.stringify([first,empty,repeated,hex(signature.sign()),signature.getAlgorithm()]);
    '''),
      jsonEncode([
        expected('unicode'),
        expected('empty'),
        expected('unicode'),
        expected('unicode'),
        'SHA256WithRSA',
      ]),
    );
  });

  test('Signature 拒绝未初始化与越界更新，失败 update 不写入部分数据', () {
    expect(
      js('''
      ${setup()}
      var signature = Signature.getInstance('SHA256WithRSA'), rejected = 0;
      try { signature.update([1]); } catch(e) { rejected++; }
      try { signature.sign(); } catch(e) { rejected++; }
      signature.initSign(key);
      for (var args of [[[1,2],-1,1],[[1,2],0,3],[[1,2],1,-1],[null]]) {
        try { signature.update.apply(signature,args); } catch(e) { rejected++; }
      }
      signature.update(java.strToBytes('中文🚀'));
      JSON.stringify([rejected,hex(signature.sign())]);
    '''),
      jsonEncode([6, expected('unicode')]),
    );
    for (final code in [
      "Packages.java.security.KeyFactory.getInstance('DSA')",
      "Packages.java.security.KeyFactory.getInstance('RSA').generatePrivate(new Packages.java.security.spec.PKCS8EncodedKeySpec([0,1,2]))",
      "Packages.java.security.Signature.getInstance('SHA256WithDSA')",
      "Packages.java.security.Signature.getInstance('SHA256WithRSA').initSign({})",
    ]) {
      expect(() => js(code), throwsA(isA<JsEvalException>()));
    }
  });

  test('jsLib 缓存的 RSA key 和 Signature 跨任务继续签名并重置消息', () {
    final cachedSource = loadBookSources(
      jsonEncode({
        'bookSourceUrl': 'https://xigua-cache.test',
        'bookSourceName': '西瓜 RSA 缓存',
        'jsLib':
            '''
        ${setup()}
        var cachedSignature = Signature.getInstance('SHA256WithRSA');
        cachedSignature.initSign(key);
        function append(bytes) { cachedSignature.update(bytes); return 'ok'; }
        function finish() { return hex(cachedSignature.sign()); }
      ''',
      }),
    ).sources.single;
    expect(js('append([65])', s: cachedSource), 'ok');
    // initSign 跨任务可复用 key，清除前一任务已积累的消息。
    expect(
      js(
        "cachedSignature.initSign(key); append(Packages.java.lang.String('中文🚀').getBytes('UTF-8'))",
        s: cachedSource,
      ),
      'ok',
    );
    expect(js('finish()', s: cachedSource), expected('unicode'));
    expect(js('finish()', s: cachedSource), expected('empty'));
  });
}
