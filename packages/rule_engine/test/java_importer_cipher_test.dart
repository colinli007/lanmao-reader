import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

void main() {
  late FakeEnvironment env;
  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  BookSource source([Map<String, Object?> extra = const {}]) => loadBookSources(
    jsonEncode({
      'bookSourceUrl': 'https://cipher.test',
      'bookSourceName': 'Java 导包与 Cipher',
      ...extra,
    }),
  ).sources.single;

  String js(String code, {BookSource? s}) => (AnalyzeRule(
    SourceTask(env, s ?? source()),
  )..setContent('外层正文')).getString('@js:$code');

  const helpers = '''
    function bytes(hex) { return hex.match(/../g).map(x => parseInt(x,16)); }
    function hex(bytes) { return bytes.map(x => (x & 255).toString(16).padStart(2,'0')).join(''); }
    var Cipher = javax.crypto.Cipher;
    var Key = javax.crypto.spec.SecretKeySpec;
    var IV = javax.crypto.spec.IvParameterSpec;
  ''';

  test('JavaImporter 构造导包、重复导包与 with 只接管导入类', () {
    expect(
      js('''
      var importer = new JavaImporter(Packages.java.lang, Packages.java.util);
      importer.importPackage(Packages.java.lang, Packages.java.util);
      var marker = '外层变量', answer;
      with (importer) {
        answer = [String('中文').getBytes('UTF-8'), result, marker,
          java.bytesToStr(Base64.getDecoder().decode('QQ==')),
          Math.max(2,3), Array.isArray(Arrays.copyOfRange([1],0,1)),
          String === Packages.java.lang.String];
      }
      JSON.stringify([answer, typeof String('a'), typeof importer.result]);
    '''),
      '[[[-28,-72,-83,-26,-106,-121],"外层正文","外层变量","A",3,true,true],"string","undefined"]',
    );
  });

  test('importClass 按短类名导入已实现的类，优先于导入的包', () {
    expect(
      js('''
      var ji = new JavaImporter(Packages.java.util);
      ji.importClass(Packages.java.lang.String, javax.crypto.Cipher, Packages.io.legado.app.help.http.StrResponse);
      var answer;
      with (ji) {
        var l = new ArrayList(); l.add('甲');
        answer = [l.size(), String('乙').getBytes('UTF-8').length, Cipher === javax.crypto.Cipher,
          typeof StrResponse, Base64 === Packages.java.util.Base64];
      }
      JSON.stringify(answer);
    '''),
      '[1,3,true,"function",true]',
    );
  });

  test('importClass 登记未实现的类，使用时才以「不支持的宿主 API」结束', () {
    final s = source({
      'jsLib': '''
        var ji = new JavaImporter();
        ji.importClass(Packages.okhttp3.HttpUrl);
        function parse(u) { with (ji) { return HttpUrl.parse(u); } }
      ''',
    });
    expect(js('typeof ji', s: s), 'object');
    expect(() => js('parse("https://a.com")', s: s),
        throwsA(isA<UnsupportedHostApiException>().having((e) => e.api, 'api', 'Packages.okhttp3.HttpUrl.parse')));
  });

  test('importClass 的参数是已实现的包或不是 Java 对象时是 JS 错误', () {
    expect(
      js('''
      var ji = new JavaImporter();
      [Packages.java.util, {}, 'java.lang.String'].map(function (x) {
        try { ji.importClass(x); return 'ok'; } catch (e) { return e instanceof TypeError; }
      }).join(',');
    '''),
      'true,true,true',
    );
  });

  test('Java 包全名与 javax 别名共享类，Base64 字节输入与缺省填充按 JDK 解码', () {
    expect(
      js('''
      JSON.stringify([
        Packages.javax.crypto.Cipher === javax.crypto.Cipher,
        Packages.javax.crypto.spec.SecretKeySpec === javax.crypto.spec.SecretKeySpec,
        Packages.java.util.Base64.getDecoder().decode('/w'),
        Packages.java.util.Base64.getDecoder().decode([81,81,61,61])
      ]);
    '''),
      '[true,true,[-1],[65]]',
    );
  });

  test('Arrays.copyOfRange 复制输入、越界尾部补零并拒绝非法范围', () {
    expect(
      js('''
      var input = [0,127,-128,-1];
      var copied = Packages.java.util.Arrays.copyOfRange(input,1,6);
      input[1] = 0; copied[0] = 5;
      var rejected = 0;
      for (var pair of [[-1,1],[5,5],[2,1]]) {
        try { Packages.java.util.Arrays.copyOfRange(input,pair[0],pair[1]); }
        catch (e) { rejected++; }
      }
      JSON.stringify([input,copied,Packages.java.util.Arrays.copyOfRange(input,4,6),
        Packages.java.util.Arrays.copyOfRange(input,4,4),rejected]);
    '''),
      '[[0,0,-128,-1],[5,-128,-1,0,0],[0,0],[],3]',
    );
  });

  test('AES ECB NoPadding 16/24/32 字节密钥匹配 JDK/FIPS 向量并可重复 doFinal', () {
    // FIPS-197 AES 向量，已用 JDK Cipher AES/ECB/NoPadding 核对。
    const vectors = {
      '000102030405060708090a0b0c0d0e0f': '69c4e0d86a7b0430d8cdb78070b4c55a',
      '000102030405060708090a0b0c0d0e0f1011121314151617':
          'dda97ca4864cdfe06eaf70a0ec0d7191',
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f':
          '8ea2b7ca516745bfeafc49904b496089',
    };
    for (final entry in vectors.entries) {
      expect(
        js('''
        $helpers
        var c = Cipher.getInstance('AES/ECB/NoPadding');
        var key = new Key(bytes('${entry.key}'),'AES');
        var plain = bytes('00112233445566778899aabbccddeeff');
        c.init(Cipher.ENCRYPT_MODE,key);
        var encrypted = c.doFinal(plain), repeated = c.doFinal(plain);
        c.init(Cipher.DECRYPT_MODE,key);
        JSON.stringify([hex(encrypted),hex(repeated),hex(c.doFinal(encrypted)),c.getIV()]);
      '''),
        '["${entry.value}","${entry.value}","00112233445566778899aabbccddeeff",null]',
      );
    }
  });

  test('AES CBC key 与 IV 的构造、getter 和 Cipher.init 均保留独立快照', () {
    // NIST SP 800-38A 首块，JDK AES/CBC/NoPadding 同值。
    expect(
      js('''
      $helpers
      var rawKey = bytes('2b7e151628aed2a6abf7158809cf4f3c');
      var rawIV = bytes('000102030405060708090a0b0c0d0e0f');
      var key = Key(rawKey,'AES'), iv = IV(rawIV);
      rawKey.fill(0); rawIV.fill(0);
      key.getEncoded().fill(1); iv.getIV().fill(1);
      var c = Cipher.getInstance('AES/CBC/NoPadding');
      c.init(1,key,iv); c.getIV().fill(2);
      var plain = bytes('6bc1bee22e409f96e93d7e117393172a');
      var encrypted = c.doFinal(plain), repeated = c.doFinal(plain);
      c.init(2,key,iv);
      JSON.stringify([hex(encrypted),hex(repeated),hex(c.doFinal(encrypted)),
        hex(key.getEncoded()),hex(iv.getIV()),key.getAlgorithm(),key.getFormat()]);
    '''),
      '["7649abac8119b246cee98e9b12e9197d","7649abac8119b246cee98e9b12e9197d",'
      '"6bc1bee22e409f96e93d7e117393172a","2b7e151628aed2a6abf7158809cf4f3c",'
      '"000102030405060708090a0b0c0d0e0f","AES","RAW"]',
    );
  });

  test('Cipher 未初始化、错误 init 与 NoPadding 非整块输入均拒绝，init 失败清旧状态', () {
    expect(
      js('''
      $helpers
      var key = Key(new Array(16).fill(0),'AES'), iv = IV(new Array(16).fill(0));
      var rejected = 0, uninitialized = 0;
      var cases = [
        ['CBC', [2,key]],
        ['CBC', [1,key,IV([0])]],
        ['ECB', [1,key,iv]],
        ['ECB', [3,key]],
        ['ECB', [1,Key([1],'AES')]],
        ['ECB', [1,Key(new Array(16).fill(0),'DES')]]
      ];
      for (var item of cases) {
        var c = Cipher.getInstance('AES/' + item[0] + '/NoPadding');
        try { c.doFinal([]); } catch(e) { uninitialized++; }
        if (item[0] === 'CBC') c.init(1,key,iv); else c.init(1,key);
        try { c.init.apply(c,item[1]); } catch(e) { rejected++; }
        try { c.doFinal(new Array(16).fill(0)); } catch(e) { uninitialized++; }
      }
      var c = Cipher.getInstance('AES/ECB/NoPadding'); c.init(1,key);
      try { c.doFinal([0]); } catch(e) { rejected++; }
      c.init(2,key);
      try { c.doFinal([0]); } catch(e) { rejected++; }
      JSON.stringify([rejected,uninitialized]);
    '''),
      '[8,12]',
    );
  });

  test('jsLib 缓存的 Cipher 跨 SourceTask 继续使用，不引用已释放任务句柄', () {
    final s = source({
      'jsLib':
          '''
        $helpers
        var cachedCipher = Cipher.getInstance('AES/ECB/NoPadding');
        cachedCipher.init(1,Key(bytes('000102030405060708090a0b0c0d0e0f'),'AES'));
        function cachedEncrypt() {
          return hex(cachedCipher.doFinal(bytes('00112233445566778899aabbccddeeff')));
        }
      ''',
    });
    expect(js('cachedEncrypt()', s: s), '69c4e0d86a7b0430d8cdb78070b4c55a');
    expect(js('cachedEncrypt()', s: s), '69c4e0d86a7b0430d8cdb78070b4c55a');
  });
}
