import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:novel_reader/app.dart';
import 'package:novel_reader/online/startup.dart';
import 'package:novel_reader/reader/reader_page.dart';
import 'package:novel_reader/storage/database.dart';

/// 端到端：本地 HTTP 服务器上的假书源，走完导入 → 搜索 → 详情 → 加入书架 → 翻页读第 1、2 章 → 切到滚动模式再读一遍 → 返回书架。
/// 用真的 worker 池和 quickjs（打包在 app 里），数据库是临时的内存数据库。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      final body = switch (path) {
        '/search' => '<div class="book"><a href="/book/1"><span class="name">本地小说</span></a><span class="author">测试作者</span></div>',
        '/book/1' => '<p class="intro">这是一本测试用的小说。</p><a class="toc" href="/book/1/toc">目录</a>',
        '/book/1/toc' => '<ul><li><a href="/c/1">第一章 开始</a></li><li><a href="/c/2">第二章 继续</a></li></ul>',
        '/c/1' => '<div id="content">第一章 开始<br>第一章的第一段。<br>第一章的第二段。</div>',
        '/c/2' => '<div id="content">第二章的第一段。<br>第二章的第二段。</div>',
        _ => null,
      };
      final response = request.response;
      if (body == null) {
        response.statusCode = 404;
      } else {
        response
          ..headers.contentType = ContentType.html
          ..write('<html><body>$body</body></html>');
      }
      response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  String sourceJson() =>
      '''{
    "bookSourceUrl": "$base", "bookSourceName": "本地测试", "searchUrl": "/search?q={{key}}",
    "ruleSearch": {"bookList": "class.book", "name": "class.name@text", "author": "class.author@text", "bookUrl": "tag.a@href"},
    "ruleBookInfo": {"intro": "class.intro@text", "tocUrl": "class.toc@href"},
    "ruleToc": {"chapterList": "tag.li", "chapterName": "tag.a@text", "chapterUrl": "tag.a@href"},
    "ruleContent": {"content": "id.content@html@js:if (chapter.title.indexOf('第一章') == 0) java.log('读到' + chapter.title); result"}
  }''';

  /// 等到 [finder] 出现（真实网络和 worker，pumpAndSettle 等不到）。
  Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('等不到 $finder');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder readerScrollable() => find.descendant(of: find.byType(ReaderPage), matching: find.byType(Scrollable)).first;

  /// 正文是自己画的，按读屏标签找：分页模式一页一个标签（各行以换行连接），滚动模式一段一个，按整行匹配。
  Finder paragraph(String text) => find.bySemanticsLabel(RegExp('(^|\n)${RegExp.escape(text)}(\n|\$)'));

  Future<void> tapReader(WidgetTester tester, double x) async {
    final size = tester.getSize(find.byType(ReaderPage));
    await tester.tapAt(Offset(size.width * x, size.height / 2));
    await tester.pumpAndSettle();
  }

  testWidgets('导入 → 搜索 → 详情 → 加入书架 → 读两章 → 返回书架', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: await startServices(database: db),
        child: const NovelReaderApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 导入
    await tester.tap(find.byTooltip('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文本导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, sourceJson());
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('新增 1 个，更新 0 个，跳过 0 个'), findsOneWidget);
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(find.text('本地测试'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 搜索
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '本地');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(tester, find.text('搜索结束，共 1 本'));
    expect(find.text('本地小说'), findsOneWidget);

    // 详情、目录、加入书架
    await tester.tap(find.text('本地小说'));
    await pumpUntil(tester, find.text('目录（2 章）'));
    expect(find.text('这是一本测试用的小说。'), findsOneWidget);
    await tester.tap(find.text('加入书架'));
    await pumpUntil(tester, find.text('已在书架'));

    // 读第一章、第二章：默认覆盖翻页，点右侧翻进第二章，点左侧翻回第一章。
    // 导入时的提示条还在底部，会挡住阅读菜单的底栏，先清掉
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.tap(find.text('开始阅读'));
    await pumpUntil(tester, paragraph('第一章的第一段。'));
    await tester.pumpAndSettle(); // 等打开阅读页的过渡动画结束，过渡期间页面不接收点击
    expect(find.bySemanticsLabel('第一章 开始\n第一章的第一段。\n第一章的第二段。'), findsOneWidget, reason: '和章节名相同的第一段被去掉');
    await tapReader(tester, 0.9);
    await pumpUntil(tester, paragraph('第二章的第一段。'));
    await tapReader(tester, 0.1);
    await pumpUntil(tester, paragraph('第一章的第一段。'));

    // 切到滚动模式，章末点下一章
    await tapReader(tester, 0.5);
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('滚动'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tapReader(tester, 0.5); // 隐藏菜单
    await tester.scrollUntilVisible(find.text('下一章'), 300, scrollable: readerScrollable());
    await tester.tap(find.text('下一章'));
    await pumpUntil(tester, paragraph('第二章的第一段。'));
    await tester.scrollUntilVisible(find.text('已是最后一章'), 300, scrollable: readerScrollable());

    // 返回书架（等滚动停下，否则这一下点击只会停住滚动）
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('本地小说'), findsOneWidget);
    expect(find.text('测试作者 · 第二章 继续'), findsOneWidget);
    final shelf = (await db.shelf()).single.book;
    expect((shelf.durChapterIndex, shelf.durChapterTitle), (1, '第二章 继续'));

    // 第一章的 java.log 到了书源日志
    await tester.tap(find.byTooltip('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书源日志'));
    await tester.pumpAndSettle();
    expect(find.text('读到第一章 开始'), findsOneWidget);
  });
}
