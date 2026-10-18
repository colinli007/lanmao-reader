import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/reader_page.dart';
import 'package:novel_reader/reader/reader_settings.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 6, paragraphs: 60);
    await services.shelveSimpleBook(chapters: 6);
  });
  tearDown(() => services.db.close());

  /// 阅读页压在一个空页面上，这样能返回。
  Future<void> open(WidgetTester tester, {int? startAt, TestServices? using}) async {
    final s = using ?? services;
    await tester.pumpWidget(
      s.app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ReaderPage(bookUrl: SimpleBook.bookUrl, startAt: startAt)),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  /// 返回：菜单里的返回按钮（菜单没显示时先点正文中部）。
  Future<void> back(WidgetTester tester) async {
    if (find.byType(BackButton).evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  Finder paragraph(int chapter, int p) => find.text('　　第$chapter章第$p段');

  /// 把某一段滚到视口顶部。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {});
    Scrollable.ensureVisible(tester.element(finder));
    await tester.pumpAndSettle();
  }

  double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

  testWidgets('第二次打开同一章直接读缓存，不发请求；同时预加载了下一章', (tester) async {
    await open(tester, startAt: 3);
    expect(paragraph(3, 0), findsOneWidget);
    expect(services.engine.calls, ['content /3.html', 'content /4.html']);
    await back(tester);
    await open(tester, startAt: 3);
    expect(services.engine.calls, hasLength(2));
  });

  testWidgets('预加载的下一章直接显示，不再请求', (tester) async {
    await open(tester, startAt: 3);
    await tester.scrollUntilVisible(find.text('下一章'), 500);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(paragraph(4, 0), findsOneWidget);
    expect(services.engine.calls.where((c) => c == 'content /4.html'), hasLength(1));
  });

  testWidgets('书源已删除：没有缓存的章节显示书源不存在，不发请求；有缓存的照常显示', (tester) async {
    await open(tester, startAt: 1);
    await back(tester);
    await services.repository.delete({SimpleBook.sourceUrl});
    services.engine.calls.clear();
    await open(tester, startAt: 1);
    expect(paragraph(1, 0), findsOneWidget);
    await back(tester);
    await open(tester, startAt: 5);
    expect(find.text('书源不存在'), findsOneWidget);
    expect(services.engine.calls, isEmpty);
  });

  testWidgets('停用书源后书架上的书照常加载', (tester) async {
    await services.repository.setEnabled({SimpleBook.sourceUrl}, false);
    await open(tester, startAt: 2);
    expect(paragraph(2, 0), findsOneWidget);
  });

  testWidgets('加载失败显示原因，重试后显示', (tester) async {
    var fail = true;
    final original = services.engine.onContent!;
    services.engine.onContent = (source, book, chapter, next) =>
        fail ? Future.error(RuleException('正文为空')) : original(source, book, chapter, next);
    await open(tester, startAt: 0);
    expect(find.textContaining('规则错误：正文为空'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(paragraph(0, 0), findsOneWidget);
  });

  testWidgets('正文链路传入下一章的地址', (tester) async {
    final nexts = <String?>[];
    final original = services.engine.onContent!;
    services.engine.onContent = (source, book, chapter, next) {
      nexts.add(next);
      return original(source, book, chapter, next);
    };
    await open(tester, startAt: 4);
    expect(nexts.first, '${SimpleBook.sourceUrl}/5.html');
    expect(nexts.last, isNull);
  });

  testWidgets('下一章停在章首；最后一章显示已是最后一章', (tester) async {
    await open(tester, startAt: 4);
    expect(find.text('上一章'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('下一章'), 500);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('第5章'), findsWidgets);
    expect(topOf(tester, paragraph(5, 0)), lessThan(200));
    await tester.scrollUntilVisible(find.text('已是最后一章'), 500);
    expect(find.text('下一章'), findsNothing);
  });

  testWidgets('上一章、下一章跳过卷，卷只显示卷名', (tester) async {
    final shelved = await services.db.chaptersOf(SimpleBook.bookUrl);
    await services.db.saveBrowsingBook(
      (await services.db.getBook(SimpleBook.bookUrl))!,
      [for (final c in shelved) c.idx == 2 ? c.copyWith(isVolume: true, title: '第二卷', url: '第二卷2') : c],
    );
    await open(tester, startAt: 1);
    await tester.scrollUntilVisible(find.text('下一章'), 500);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(paragraph(3, 0), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一章'));
    await tester.pumpAndSettle();
    expect(paragraph(1, 0), findsOneWidget);
    expect(services.engine.calls.where((c) => c.contains('第二卷')), isEmpty);
  });

  testWidgets('点正文中部显示菜单，目录里标出当前章节，点击跳转', (tester) async {
    await open(tester, startAt: 3);
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    expect(find.text('三体'), findsOneWidget);
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    final current = tester.widget<ListTile>(find.widgetWithText(ListTile, '第3章'));
    expect(current.selected, isTrue);
    await tester.tap(find.widgetWithText(ListTile, '第1章'));
    await tester.pumpAndSettle();
    expect(paragraph(1, 0), findsOneWidget);
    // 再点一次中部隐藏菜单
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('目录'), findsNothing);
  });

  testWidgets('章节很短时点正文中部也能打开菜单', (tester) async {
    await services.useSimpleBook(chapters: 6, paragraphs: 1);
    await open(tester, startAt: 0);
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('调大字号后第一个可见段落仍在顶部附近', (tester) async {
    await open(tester, startAt: 3);
    await scrollTo(tester, paragraph(3, 20));
    final container = ProviderScope.containerOf(tester.element(find.byType(ReaderPage)));
    container.read(readerSettingsProvider.notifier).update(const ReaderSettings(fontSize: 24));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(paragraph(3, 20));
    expect(text.style?.fontSize, 24);
    expect(topOf(tester, paragraph(3, 20)), inInclusiveRange(0, 80));
  });

  testWidgets('主题在设置里切换，对所有书生效并落盘', (tester) async {
    await open(tester, startAt: 0);
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暗'));
    await tester.pumpAndSettle();
    expect((await services.db.loadSettings())['reader.theme'], 'dark');
    Navigator.of(tester.element(find.text('暗'))).pop();
    await tester.pumpAndSettle();
    await back(tester);
    await open(tester, startAt: 1);
    final scaffold = tester.widget<Scaffold>(find.descendant(of: find.byType(ReaderPage), matching: find.byType(Scaffold)).first);
    expect(scaffold.backgroundColor, ReaderTheme.dark.background);
  });

  testWidgets('离开时保存进度；换了窗口尺寸重新打开，同一段落回到顶部', (tester) async {
    await open(tester, startAt: 5);
    await scrollTo(tester, paragraph(5, 30));
    await back(tester);
    final book = (await services.db.getBook(SimpleBook.bookUrl))!;
    expect((book.durChapterIndex, book.durChapterUrl, book.durChapterTitle), (5, '/5.html', '第5章'));
    expect(book.durChapterPos, greaterThan(0));
    expect(book.lastReadAt, isNotNull);

    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    await open(tester);
    expect(topOf(tester, paragraph(5, 30)), inInclusiveRange(0, 60));
  });

  testWidgets('重启后从书架进入，回到上次的章节和段落，缓存的正文不再请求', (tester) async {
    final dir = Directory.systemTemp.createTempSync('reader');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    var app = await TestServices.create(file: file);
    await app.useSimpleBook(chapters: 6, paragraphs: 60);
    await app.shelveSimpleBook(chapters: 6);
    await open(tester, startAt: 4, using: app);
    await scrollTo(tester, paragraph(4, 25));
    await back(tester);
    await tester.pumpWidget(const SizedBox());
    await app.db.close();

    app = await TestServices.create(file: file);
    await app.useSimpleBook(chapters: 6, paragraphs: 60);
    await app.db.purgeBrowsingBooks();
    expect((await app.db.shelf()).single.book.bookUrl, SimpleBook.bookUrl);
    app.engine.calls.clear();
    await open(tester, using: app);
    expect(topOf(tester, paragraph(4, 25)), inInclusiveRange(0, 60));
    expect(app.engine.calls.where((c) => c == 'content /4.html'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await app.db.close();
  });
}

