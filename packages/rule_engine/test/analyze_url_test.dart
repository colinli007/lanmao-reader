import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/request/analyze_url.dart';
import 'package:test/test.dart';

// source-request 规格里请求构造部分的场景，行为对照 MD3 的 AnalyzeUrl
void main() {
  BookSource source([Map<String, Object?> extra = const {}]) =>
      loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': 'A', ...extra})).sources.single;

  SourceRequest build(String url, {String? key, int? page, Map<String, Object?> extra = const {}}) =>
      buildSourceRequest(url, key: key, page: page, baseUrl: 'https://a.com', source: source(extra));

  group('URL 模板', () {
    test('搜索地址', () {
      final request = build('/search?q={{key}}&p={{page}}', key: '三体', page: 2);
      expect(request.http.url, 'https://a.com/search?q=%E4%B8%89%E4%BD%93&p=2');
      expect(request.http.method, 'GET');
      expect(request.url, 'https://a.com/search?q=三体&p=2');
    });

    test('页码列表', () {
      expect(build('/list<,_2,_3>.html', page: 1).url, 'https://a.com/list.html');
      expect(build('/list<,_2,_3>.html', page: 2).url, 'https://a.com/list_2.html');
      expect(build('/list<,_2,_3>.html', page: 5).url, 'https://a.com/list_3.html');
    });

    test('页码 0 按第 1 页处理（MD3 越界）', () {
      expect(build('/list<a,b>.html', page: 0).url, 'https://a.com/lista.html');
    });

    test('模板里有表达式', () {
      expect(
        () => build('/s?p={{page*10}}', page: 1),
        throwsA(isA<NeedsJsException>().having((e) => e.snippet, 'snippet', '{{page*10}}')),
      );
    });

    test('地址里有 @js:', () {
      expect(() => build('/s@js:result+1'), throwsA(isA<NeedsJsException>()));
    });

    test('baseUrl 和没有搜索词时的 key', () {
      expect(build('{{baseUrl}}/x?k={{key}}').url, 'https://a.com/x?k=');
    });
  });

  group('URL 选项', () {
    test('宽松 JSON 选项', () {
      final request = build("/search,{'method':'POST','body':'q={{key}}'}", key: '三体');
      expect(request.http.method, 'POST');
      expect(request.http.url, 'https://a.com/search');
      expect(request.http.body, 'q=%E4%B8%89%E4%BD%93');
      expect(request.http.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=utf-8');
    });

    test('webView 选项', () {
      expect(() => build('/s,{"webView": true}'), throwsA(isA<NeedsWebViewException>()));
      // 数字 0 也算真；false 和 "false" 算假
      expect(() => build('/s,{"webView": 0}'), throwsA(isA<NeedsWebViewException>()));
      expect(build('/s,{"webView": "false"}').http.method, 'GET');
    });

    test('js 和 bodyJs 选项需要 JS', () {
      expect(() => build('/s,{"js": "result"}'), throwsA(isA<NeedsJsException>()));
      expect(() => build('/s,{"bodyJs": "result"}'), throwsA(isA<NeedsJsException>()));
    });

    test('对象形式的 body 带缩进发送', () {
      final request = build('/s,{"method":"POST","body":{"keyword":{{key}},"page_index":{{page}},"none":null}}', key: '三体', page: 1);
      expect(request.http.body, '{\n  "keyword": "三体",\n  "page_index": 1\n}');
      expect(request.http.headers['Content-Type'], 'application/json; charset=UTF-8');
    });

    test('headers 覆盖书源请求头', () {
      final request = build('/s,{"headers":{"Referer":"https://b.com/","X-N":1}}', extra: {'header': '{"Referer":"https://a.com/"}'});
      expect(request.http.headers['Referer'], 'https://b.com/');
      expect(request.http.headers['X-N'], '1');
    });

    test('retry、type', () {
      expect(build('/s,{"retry": 2}').http.retry, 2);
      expect(build('/s,{"retry": "3"}').http.retry, 0);
      expect(build('/s,{"type": "zip"}').type, 'zip');
    });

    test('选项解析不了时按没有选项处理', () {
      final request = build('/s,{method:POST,}');
      expect(request.http.method, 'GET');
      expect(request.url, 'https://a.com/s');
    });

    test('HEAD 去掉查询串', () {
      expect(build('/s?a=1,{"method":"head"}').http.url, 'https://a.com/s');
    });
  });

  group('请求参数编码', () {
    test('GBK 搜索词', () {
      expect(build('/s?q={{key}},{"charset":"gbk"}', key: '三体').http.url, 'https://a.com/s?q=%C8%FD%CC%E5');
    });

    test('已编码的查询串原样发送', () {
      expect(build('/s?q=%E4%B8%89').http.url, 'https://a.com/s?q=%E4%B8%89');
    });

    test('空格编码为 %20，保留安全字符', () {
      expect(build('/s?q=a b&x={y}|').http.url, 'https://a.com/s?q=a%20b&x={y}|');
    });

    test('escape 编码', () {
      expect(build('/s?q={{key}}&n=1,{"charset":"escape"}', key: '三体 a').http.url, 'https://a.com/s?q=%u4e09%u4f53%20a&n=1');
    });

    test('POST 表单：空格编码为 +，指定 charset 时已编码的值会被二次编码', () {
      expect(build('/s,{"method":"POST","body":"q=a b&k=%E4"}').http.body, 'q=a+b&k=%E4');
      expect(build('/s,{"method":"POST","body":"k=%E4","charset":"gbk"}').http.body, 'k=%25E4');
      expect(build('/s,{"method":"POST","body":"q={{key}}","charset":"gbk"}', key: '三体').http.body, 'q=%C8%FD%CC%E5');
    });

    test('指定了 Content-Type 时原样发送', () {
      final request = build('/s,{"method":"POST","body":"a b","headers":{"Content-Type":"text/plain"}}');
      expect(request.http.body, 'a b');
      expect(request.http.headers['Content-Type'], 'text/plain; charset=utf-8');
    });

    test('没有 Content-Type 的 XML 按 JSON 发送', () {
      final request = build('/s,{"method":"POST","body":"<a>1</a>"}');
      expect(request.http.body, '<a>1</a>');
      expect(request.http.headers['Content-Type'], 'application/json; charset=UTF-8');
    });

    test('不支持的编码', () {
      expect(() => build('/s?q=三,{"charset":"big5"}'), throwsA(isA<RuleException>()));
    });
  });

  group('请求头', () {
    test('书源请求头', () {
      final request = build('/s', extra: {'header': '{"Referer":"https://a.com/"}'});
      expect(request.http.headers['Referer'], 'https://a.com/');
      expect(request.http.headers['User-Agent'], defaultUserAgent);
    });

    test('宽松 JSON 请求头，自带 UA', () {
      final request = build('/s', extra: {'header': "{'user-agent': 'okhttp/4.9.2'}"});
      expect(request.http.headers, {'user-agent': 'okhttp/4.9.2'});
    });

    test('UA 为 null 时不发送', () {
      expect(build('/s', extra: {'header': '{"User-Agent":"null"}'}).http.headers.containsKey('User-Agent'), isFalse);
    });

    test('JS 请求头', () {
      expect(() => build('/s', extra: {'header': '@js:({})'}), throwsA(isA<NeedsJsException>()));
    });

    test('书源的 Cookie 设置和限速带到请求上', () {
      final request = build('/s', extra: {'enabledCookieJar': true, 'concurrentRate': '500'});
      expect(request.http.sourceUrl, 'https://a.com');
      expect(request.http.enabledCookieJar, isTrue);
      expect(request.http.concurrentRate, '500');
    });
  });
}
