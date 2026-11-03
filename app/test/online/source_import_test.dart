import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/import_text.dart';
import 'package:lanmao_reader/online/source_import.dart';

import '../support/test_app.dart';

void main() {
  late HttpServer server;
  late String base;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final response = request.response;
      if (request.uri.path == '/sources.json') {
        response.write('[{"bookSourceUrl":"https://a.com","bookSourceName":"甲"}]');
      } else {
        response.statusCode = 404;
      }
      response.close();
    });
  });
  tearDown(() => server.close(force: true));

  test('从网址下载书源，按 UTF-8 解码', () async {
    expect(await downloadText('$base/sources.json'), contains('"甲"'));
  });

  test('404 和不是网址时给出原因', () async {
    await expectLater(
      downloadText('$base/missing'),
      throwsA(isA<ImportException>().having((e) => e.reason, 'reason', '下载失败：HTTP 404')),
    );
    await expectLater(downloadText('abc'), throwsA(isA<ImportException>().having((e) => e.reason, 'reason', '不是有效的网址')));
  });

  test('预览：同一地址出现多次只算一次，以最后一次为准', () async {
    final services = await TestServices.create();
    await services.addSources([{'bookSourceUrl': 'https://a.com'}]);
    final preview = previewImport(
      '[{"bookSourceUrl":"https://a.com","bookSourceName":"1"},{"bookSourceUrl":"https://b.com"},{"bookSourceUrl":"https://a.com","bookSourceName":"2"},3]',
      services.repository,
    );
    expect((preview.added, preview.updated, preview.skipped.single.index), (1, 1, 3));
    expect([for (final s in preview.sources) s.bookSourceName], ['2', '']);
    await services.db.close();
  });
}
