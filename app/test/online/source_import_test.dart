import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/import_text.dart';
import 'package:lanmao_reader/online/source_import.dart';
import 'package:rule_engine/rule_engine.dart' show defaultUserAgent;

import '../support/test_app.dart';

void main() {
  late HttpServer server;
  late String base;

  /// 收到的请求：路径和 User-Agent（没有时为 null）。
  late List<(String, String?)> requests;
  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      requests.add((request.uri.path, request.headers.value(HttpHeaders.userAgentHeader)));
      final response = request.response;
      switch (request.uri.path) {
        case '/sources.json':
          response.write('[{"bookSourceUrl":"https://a.com","bookSourceName":"甲"}]');
        case '/more.json':
          response.write('[{"bookSourceUrl":"https://b.com"},{"bookSourceName":"没有地址"}]');
        case '/list.json':
          response.write('{"sourceUrls":["$base/sources.json"]}');
        case '/not_login':
          response.write('{"msg":{"user_not_login":"用户未登录"},"code":1000}');
        default:
          response.statusCode = 404;
      }
      response.close();
    });
  });
  tearDown(() => server.close(force: true));

  test('从网址下载书源，按 UTF-8 解码，带书源请求的默认 User-Agent', () async {
    expect(await downloadText('$base/sources.json'), contains('"甲"'));
    expect(requests, [('/sources.json', defaultUserAgent)]);
  });

  test('网址以 #requestWithoutUA 结尾时去掉标记、不带 User-Agent', () async {
    expect(await downloadText('$base/sources.json#requestWithoutUA'), contains('"甲"'));
    expect(requests, [('/sources.json', null)]);
  });

  test('404 和不是网址时给出原因', () async {
    await expectLater(
      downloadText('$base/missing'),
      throwsA(isA<ImportException>().having((e) => e.reason, 'reason', '下载失败：HTTP 404')),
    );
    await expectLater(downloadText('abc'), throwsA(isA<ImportException>().having((e) => e.reason, 'reason', '不是有效的网址')));
  });

  group('预览', () {
    late TestServices services;
    setUp(() async => services = await TestServices.create());
    tearDown(() => services.db.close());

    Matcher failsWith(String reason) => throwsA(isA<ImportException>().having((e) => e.reason, 'reason', reason));

    test('同一地址出现多次只算一次，以最后一次为准', () async {
      await services.addSources([{'bookSourceUrl': 'https://a.com'}]);
      final preview = await previewImport(
        '[{"bookSourceUrl":"https://a.com","bookSourceName":"1"},{"bookSourceUrl":"https://b.com"},{"bookSourceUrl":"https://a.com","bookSourceName":"2"},3]',
        services.repository,
      );
      expect((preview.added, preview.updated), (1, 1));
      expect(preview.skipped, ['第 4 项：不是 JSON 对象']);
      expect([for (final s in preview.sources) s.bookSourceName], ['2', '']);
    });

    test('下载到的是网站的错误信息：不是书源，附上内容开头', () async {
      await expectLater(
        previewImport(await downloadText('$base/not_login'), services.repository),
        failsWith('不是书源。内容开头：{"msg":{"user_not_login":"用户未登录"},"code":1000}'),
      );
    });

    test('不是合法 JSON：合并空白，超过 100 个字符时截断', () async {
      await expectLater(previewImport('hello', services.repository), failsWith('不是书源。内容开头：hello'));
      await expectLater(
        previewImport('<html>\n  <body>${'书' * 120}</body>', services.repository),
        failsWith('不是书源。内容开头：<html> <body>${'书' * 87}…'),
      );
    });

    test('整份是订阅源、空数组时各自说明', () async {
      await expectLater(
        previewImport('[{"sourceUrl":"https://r1.com"},{"sourceUrl":"https://r2.com"}]', services.repository),
        failsWith('这是订阅源，不是书源，暂不支持订阅源'),
      );
      await expectLater(previewImport('[]', services.repository), failsWith('内容里没有书源'));
    });

    test('网址列表：逐个下载合并，失败的网址和网址里跳过的条目写进跳过列表', () async {
      final preview = await previewImport(
        '{"sourceUrls":["$base/sources.json","$base/missing","$base/more.json","$base/not_login","$base/list.json"]}',
        services.repository,
      );
      expect([for (final s in preview.sources) s.bookSourceUrl], ['https://a.com', 'https://b.com']);
      expect(preview.added, 2);
      expect(preview.skipped, [
        '$base/missing：下载失败：HTTP 404',
        '$base/more.json 第 2 项：缺少书源地址',
        '$base/not_login：不是书源。内容开头：{"msg":{"user_not_login":"用户未登录"},"code":1000}',
        '$base/list.json：内容里没有书源',
      ]);
    });
  });
}
