import 'package:rule_engine/src/text/lenient_json.dart';
import 'package:test/test.dart';

// 用例取自 aoaostar/legado 书源里严格 JSON 解析不了的 header 和 URL 选项
void main() {
  test('单引号和换行', () {
    expect(parseLenientJson("{\n'method': 'POST',\n'body': 's=articlename&searchkey=三体&Submit='\n}"), {
      'method': 'POST',
      'body': 's=articlename&searchkey=三体&Submit=',
    });
    expect(parseLenientJson("{\n'charset': 'gbk'\n}"), {'charset': 'gbk'});
  });

  test('等号作键值分隔', () {
    expect(parseLenientJson('{"type"="app"}'), {'type': 'app'});
    expect(parseLenientJson('{a=>1}'), {'a': 1});
  });

  test('模板替换后没有引号的值', () {
    expect(parseLenientJson('{"method":"POST","body":{"keyword":三体,"page_index":1,"page_size":20}}'), {
      'method': 'POST',
      'body': {'keyword': '三体', 'page_index': 1, 'page_size': 20},
    });
  });

  test('不带引号的键和布尔值', () {
    expect(parseLenientJson('{webView: true, retry: 2, x: null}'), {'webView': true, 'retry': 2, 'x': null});
    expect(parseLenientJson("{'webView': TRUE}"), {'webView': true});
  });

  test('字符串里的原始换行', () {
    expect(parseLenientJson('{\n  "method": "POST",\n  "body": "a=1&&\nb=2"\n}'), {'method': 'POST', 'body': 'a=1&&\nb=2'});
  });

  test('注释和分号', () {
    expect(parseLenientJson('{a:1; /* x */ b:2 # y\n}'), {'a': 1, 'b': 2});
  });

  test('数组里多余的逗号按 null 处理，对象末尾的逗号是错误', () {
    expect(parseLenientJson('[1,,2,]'), [1, null, 2, null]);
    expect(() => parseLenientJson('{a:1,}'), throwsFormatException);
  });

  test('不是一个完整的 JSON 值时报错', () {
    expect(() => parseLenientJson('"User-Agent": "Mozilla/5.0"'), throwsFormatException);
    expect(() => parseLenientJson('{"a":"1"'), throwsFormatException);
    expect(() => parseLenientJson(''), throwsFormatException);
  });

  test('转义', () {
    expect(parseLenientJson(r"'a\'b中\n'"), "a'b中\n");
    expect(() => parseLenientJson(r'"\x"'), throwsFormatException);
  });

  test('请求头按字符串映射读取', () {
    expect(
      parseLenientStringMap("{\n'headers': {\n    'User-Agent': 'Referer: http://qbtr.cc/'\n    }\n}"),
      {'headers': '{"User-Agent":"Referer: http://qbtr.cc/"}'},
    );
    expect(parseLenientStringMap("{'User-Agent': 'okhttp/4.9.2', 'n': 1, 'b': false, 'z': null}"), {
      'User-Agent': 'okhttp/4.9.2',
      'n': '1',
      'b': 'false',
    });
    expect(() => parseLenientStringMap('[1]'), throwsFormatException);
  });
}
