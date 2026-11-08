import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/app.dart';
import 'package:lanmao_reader/online/startup.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/settings/byte_size.dart';
import 'package:lanmao_reader/storage/database.dart';

/// 端到端：本地 HTTP 服务器上的假书源，走完导入书源和替换规则 → 搜索 → 详情 → 加入书架 → 翻页读第 1、2 章 → 切到滚动模式再读一遍 → 返回书架
/// → 清除正文缓存后再打开 → 导入第二个书源，在书架上换过去，从对齐到的章节继续。
/// 用真的 worker 池和 quickjs（打包在 app 里），数据库是临时的内存数据库。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 让测试接管文字输入通道：不接管时 enterText 用 -1 作输入连接编号，框架只在 debug 构建里（assert）放行它，
  // profile 构建会静默丢掉输入的文字。iOS 26 真机上 debug 构建起不来（JIT），只能用 profile 跑
  binding.testTextInput.register();

  late HttpServer server;
  late String base;

  /// 每个路径被请求的次数。
  final hits = <String, int>{};

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      hits.update(path, (n) => n + 1, ifAbsent: () => 1);
      final body = switch (path) {
        '/search' => '<div class="book"><a href="/book/1"><span class="name">本地小说</span></a><span class="author">测试作者</span></div>',
        '/book/1' => '<p class="intro">这是一本测试用的小说。</p><a class="toc" href="/book/1/toc">目录</a>',
        '/book/1/toc' => '<ul><li><a href="/c/1">第一章 开始</a></li><li><a href="/c/2">第二章 继续</a></li></ul>',
        '/c/1' => '<div id="content">第一章 开始<br>第一章的第一段。<br>第一章的第二段。<br>请记住本站域名 www.example.com</div>',
        '/c/2' => '<div id="content">第二章的第一段。<br>第二章的第二段。</div>',
        // 第二个书源：同一本书，目录前面多一个卷，章节名的写法不同
        '/b/search' => '<div class="book"><a href="/b/book/1"><span class="name">本地小说</span></a><span class="author">测试作者</span></div>',
        '/b/book/1' => '<p class="intro">备用书源上的这本书。</p><a class="toc" href="/b/book/1/toc">目录</a>',
        '/b/book/1/toc' =>
          '<ul><li><b data-v="1">正文卷</b></li><li><a href="/b/c/1">第1章 开始</a></li><li><a href="/b/c/2">第2章：继续</a></li></ul>',
        '/b/c/1' => '<div id="content">备用书源第一章的第一段。</div>',
        '/b/c/2' => '<div id="content">备用书源第二章的第一段。</div>',
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

  String secondSourceJson() =>
      '''{
    "bookSourceUrl": "$base/b", "bookSourceName": "本地备用", "searchUrl": "/b/search?q={{key}}",
    "ruleSearch": {"bookList": "class.book", "name": "class.name@text", "author": "class.author@text", "bookUrl": "tag.a@href"},
    "ruleBookInfo": {"intro": "class.intro@text", "tocUrl": "class.toc@href"},
    "ruleToc": {"chapterList": "tag.li", "chapterName": "text", "chapterUrl": "tag.a@href", "isVolume": "tag.b@data-v"},
    "ruleContent": {"content": "id.content@html"}
  }''';

  /// 书架 → 设置 → 书源 → 粘贴导入一个书源 → 回到书架。
  Future<void> importSource(WidgetTester tester, String json, String name) async {
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文本导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, json);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('新增 1 个，更新 0 个，跳过 0 个'), findsOneWidget);
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
  }

  /// 书架 → 设置 → 替换净化规则 → 粘贴导入一条去掉「请记住本站」的规则 → 回到书架。
  Future<void> importReplaceRule(WidgetTester tester) async {
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('替换净化规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴文本导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '[{"id": 1, "name": "去本站广告", "pattern": "请记住本站.*"}]');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('新增 1 条，更新 0 条，跳过 0 条'), findsOneWidget);
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(find.text('去本站广告'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
  }

  /// 长按书架上的书，弹出选项单。直接触发这本书的「长按」语义动作，不用 `tester.longPress`：
  /// 在设备上跑集成测试时，用 `tester.longPress` 长按过以后这本书再也点不开，原因没有查清；
  /// 组件测试里和真机上手动长按都正常（redesign-minimal-ui 任务 8.2）。长按手势本身由组件测试覆盖。
  Future<void> longPressBook(WidgetTester tester, String name) async {
    final handle = tester.ensureSemantics();
    var node = tester.getSemantics(find.text(name).first);
    while (!node.getSemanticsData().hasAction(SemanticsAction.longPress)) {
      node = node.parent!;
    }
    tester.binding.performSemanticsAction(SemanticsActionEvent(type: SemanticsAction.longPress, viewId: tester.view.viewId, nodeId: node.id));
    await tester.pumpAndSettle();
    handle.dispose();
  }

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

  testWidgets('导入书源和替换规则 → 搜索 → 详情 → 加入书架 → 读两章 → 返回书架 → 清除缓存后再打开 → 换书源', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: await startServices(database: db),
        child: const NovelReaderApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 导入书源和替换规则
    await importSource(tester, sourceJson(), '本地测试');
    await importReplaceRule(tester);

    // 搜索
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '本地');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(tester, find.text('搜索结束，共 1 本'));
    expect(find.text('本地小说'), findsOneWidget);

    // 详情、目录、加入书架
    await tester.tap(find.text('本地小说'));
    await pumpUntil(tester, find.text('共 2 章'));
    expect(find.text('这是一本测试用的小说。'), findsOneWidget);
    await tester.tap(find.text('加入书架'));
    await pumpUntil(tester, find.text('已在书架'));

    // 读第一章、第二章：默认覆盖翻页，点右侧翻进第二章，点左侧翻回第一章。
    // 导入时的提示条还在底部，会挡住阅读菜单的底栏，先清掉
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.tap(find.text('开始阅读'));
    await pumpUntil(tester, paragraph('第一章的第一段。'));
    await tester.pumpAndSettle(); // 等打开阅读页的过渡动画结束，过渡期间页面不接收点击
    expect(
      find.bySemanticsLabel('第一章 开始\n第一章的第一段。\n第一章的第二段。'),
      findsOneWidget,
      reason: '和章节名相同的第一段被去掉，广告被替换净化规则去掉',
    );
    expect([for (final row in await db.select(db.contents).get()) row.content], contains(contains('请记住本站域名')), reason: '缓存里是原文');
    await tapReader(tester, 0.9);
    await pumpUntil(tester, paragraph('第二章的第一段。'));
    await tapReader(tester, 0.1);
    await pumpUntil(tester, paragraph('第一章的第一段。'));

    // 切到滚动模式，章末点下一章
    await tapReader(tester, 0.5);
    await tester.tap(find.byTooltip('排版'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('滚动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('滚动'));
    await tester.pumpAndSettle();
    // 先收起面板：排版面板最高占屏幕的六成，macOS 默认窗口这样的矮屏上会盖住正中间
    await tester.tap(find.byTooltip('排版'));
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
    await tester.pageBack(); // 详情页 → 搜索页
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消')); // 搜索页 → 书架
    await tester.pumpAndSettle();
    expect(find.text('本地小说'), findsWidgets);
    final shelf = (await db.shelf()).single.book;
    expect((shelf.durChapterIndex, shelf.durChapterTitle), (1, '第二章 继续'));

    // 第一章的 java.log 到了书源日志
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书源日志'));
    await tester.pumpAndSettle();
    expect(find.text('读到第一章 开始'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 清除正文缓存（已经在设置页），再从书架打开：停在第二章，正文重新请求网络
    expect(find.text('2 章 · ${formatByteSize((await db.contentCacheStats()).bytes)}'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '清除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();
    expect(find.text('0 章 · 0 B'), findsOneWidget);
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    final before = hits['/c/2'];
    await tester.tap(find.text('本地小说').first);
    await pumpUntil(tester, paragraph('第二章的第一段。'));
    expect(hits['/c/2'], before! + 1);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 导入第二个书源，在书架上换过去：第二章对齐到「第2章：继续」（新目录里的序号 2），章内位置不变
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await importSource(tester, secondSourceJson(), '本地备用');
    final old = (await db.shelf()).single.book;
    await longPressBook(tester, '本地小说');
    await tester.tap(find.text('换书源'));
    await pumpUntil(tester, find.text('本地备用'));
    expect(find.text('当前'), findsOneWidget);
    await tester.tap(find.text('本地备用'));
    await pumpUntil(tester, find.text('已换到本地备用'));
    final moved = (await db.shelf()).single.book;
    expect((moved.originName, moved.durChapterIndex, moved.durChapterTitle), ('本地备用', 2, '第2章：继续'));
    expect((moved.durChapterPos, moved.lastReadAt), (old.durChapterPos, old.lastReadAt));
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地小说').first);
    await pumpUntil(tester, paragraph('备用书源第二章的第一段。'));
    expect(hits['/b/c/2'], 1);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    // 阅读页直接换回原书源，仍停在第二章，返回一次就是书架。
    await tester.tap(find.byTooltip('换书源'));
    await pumpUntil(tester, find.text('本地测试'));
    await tester.tap(find.text('本地测试'));
    await pumpUntil(tester, paragraph('第二章的第一段。'));
    final readerChanged = (await db.shelf()).single.book;
    expect((readerChanged.originName, readerChanged.durChapterIndex), ('本地测试', 1));
    expect(await db.getBook(moved.bookUrl), isNull);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });
}
