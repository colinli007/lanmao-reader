import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

// 「链路在 worker 中执行」：本地 HTTP 服务 + worker 池 + RuleHost
void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response..headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/s':
          await Future<void>.delayed(const Duration(seconds: 5));
          response.write('<div class="item"><h3>甲</h3><a href="/b/1">x</a></div>');
        case '/b/1':
          response.write('<h1>三体</h1><ul><li><a href="/c/1">第一章</a></li><li><a href="/c/2">第二章</a></li></ul>');
        case '/c/1':
          response.write('<div id="c"><p>正文一</p></div>');
        default:
          response.statusCode = 404;
      }
      await response.close();
    });
  });

  tearDown(() => server.close(force: true));

  BookSource source() => loadBookSources('''{
    "bookSourceUrl": "$base", "bookSourceName": "本地", "searchUrl": "/s?q={{key}}",
    "ruleSearch": {"bookList": "class.item", "name": "tag.h3@text", "bookUrl": "tag.a@href"},
    "ruleBookInfo": {"name": "tag.h1@text"},
    "ruleToc": {"chapterList": "tag.li", "chapterName": "tag.a@text", "chapterUrl": "tag.a@href"},
    "ruleContent": {"content": "id.c@html"}
  }''').sources.single;

  test('取消一次搜索：20 个任务都收到取消错误', () async {
    final pool = WorkerPool(RuleHost().handle, size: 4);
    addTearDown(pool.close);
    final token = CancelToken();
    final futures = [for (var i = 0; i < 20; i++) pool.run(searchTask(source(), '书$i'), cancelToken: token)];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    for (final future in futures) {
      await expectLater(future, throwsA(isA<TaskCancelledException>()));
    }
  });

  test('详情、目录、正文在 worker 里跑通', () async {
    final pool = WorkerPool(RuleHost().handle, size: 2);
    addTearDown(pool.close);
    final s = source();
    final book = await pool.run(bookInfoTask(s, Book.of(s, '$base/b/1')));
    expect(book.name, '三体');
    expect(book.tocHtml, isNotNull);
    final (book: tocBook, :chapters) = await pool.run(chapterListTask(s, book));
    expect(chapters.map((c) => c.title), ['第一章', '第二章']);
    expect(tocBook.totalChapterNum, 2);
    final content = await pool.run(contentTask(s, tocBook, chapters.first, nextChapterUrl: chapters[1].url));
    expect(content.content, '　　正文一');
  });

  test('链路的错误能传回提交方，带着书源名和字段', () async {
    final pool = WorkerPool(RuleHost().handle, size: 1);
    addTearDown(pool.close);
    final json =
        '{"bookSourceUrl":"$base","bookSourceName":"本地","ruleBookInfo":{"name":"tag.h1@text@js:java.getVerificationCode(result)"}}';
    final s = loadBookSources(json).sources.single;
    await expectLater(
      pool.run(bookInfoTask(s, Book.of(s, '$base/b/1'))),
      throwsA(
        isA<UnsupportedHostApiException>()
            .having((e) => e.api, 'api', 'java.getVerificationCode')
            .having((e) => e.field, 'field', 'ruleBookInfo.name')
            .having((e) => e.sourceName, 'source', '本地'),
      ),
    );
  });
}
