import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

void main() {
  test('请求可以按 JSON 往返', () {
    const request = HttpRequest(
      url: 'https://a.com/s?q=1',
      method: 'POST',
      headers: {'Referer': 'https://a.com/'},
      body: 'q=1',
      sourceUrl: 'https://a.com',
      enabledCookieJar: true,
      concurrentRate: '500',
      retry: 2,
    );
    expect(HttpRequest.fromJson(request.toJson()).toJson(), request.toJson());
  });

  test('错误带上书源和字段', () {
    final error = NeedsJsException('@js:result.trim()', sourceName: '某书源', field: 'ruleSearch.name');
    expect(error.toString(), '需要 JS 引擎：@js:result.trim()（某书源 ruleSearch.name）');
  });
}
