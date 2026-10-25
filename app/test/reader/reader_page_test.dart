import 'dart:async';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/layout/page_painter.dart';
import 'package:novel_reader/reader/paged/paged_view.dart';
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

  /// 阅读页压在一个空页面上，这样能返回。正文是自己画的，用读屏标签找段落（testWidgets 默认打开语义树）。
  Future<void> open(WidgetTester tester, {int? startAt, TestServices? using}) async {
    final s = using ?? services;
    await tester.pumpWidget(
      s.app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(bookUrl: SimpleBook.bookUrl, startAt: startAt),
                ),
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

  ReaderSettingsNotifier settingsOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ReaderPage))).read(readerSettingsProvider.notifier);

  Future<void> update(WidgetTester tester, ReaderSettings Function(ReaderSettings settings) change) async {
    final notifier = settingsOf(tester);
    notifier.update(change(ProviderScope.containerOf(tester.element(find.byType(ReaderPage))).read(readerSettingsProvider)));
    await tester.pumpAndSettle();
  }

  Future<void> useScroll(WidgetTester tester) => update(tester, (s) => s.copyWith(pageMode: PageMode.scroll));

  /// 返回：菜单里的返回按钮（菜单没显示时先点正文中部）。
  Future<void> back(WidgetTester tester) async {
    if (find.byType(BackButton).evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  /// 第 [chapter] 章第 [p] 段：滚动模式里一段一个标签，分页模式里一页一个标签（各行以换行连接），按整行匹配。
  Finder paragraph(int chapter, int p) => find.bySemanticsLabel(RegExp('(^|\n)第$chapter章第$p段(\n|\$)'));

  /// 分页模式当前页的文字。
  String pageText(WidgetTester tester) => tester.getSemantics(find.bySemanticsLabel(RegExp(r'第\d+章第\d+段')).first).label;

  /// 当前页第一段的段号。
  String firstParagraph(WidgetTester tester) => RegExp(r'第\d+章第\d+段').firstMatch(pageText(tester))!.group(0)!;

  Future<void> tapRight(WidgetTester tester) async {
    await tester.tapAt(Offset(tester.getSize(find.byType(ReaderPage)).width - 20, 300));
    await tester.pumpAndSettle();
  }

  Future<void> tapLeft(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
  }

  /// 往后翻，直到出现 [finder]。
  Future<void> turnUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await tapRight(tester);
    }
    expect(finder, findsOneWidget);
  }

  /// 把某一段滚到视口顶部（滚动模式）。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final delta = tester.getTopLeft(finder).dy - tester.getTopLeft(find.byType(Scrollable).first).dy;
    scrollable.position.jumpTo(scrollable.position.pixels + delta);
    await tester.pumpAndSettle();
  }

  double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

  group('加载与预加载', () {
    testWidgets('第二次打开同一章直接读缓存，不发请求；同时预加载了下一章和上一章', (tester) async {
      await open(tester, startAt: 3);
      expect(paragraph(3, 0), findsOneWidget);
      expect(services.engine.calls, ['content /3.html', 'content /4.html', 'content /2.html']);
      await back(tester);
      await open(tester, startAt: 3);
      expect(services.engine.calls, hasLength(3));
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
      final nexts = <String, String?>{};
      final original = services.engine.onContent!;
      services.engine.onContent = (source, book, chapter, next) {
        nexts[chapter.url] = next;
        return original(source, book, chapter, next);
      };
      await open(tester, startAt: 4);
      expect(nexts['/4.html'], '${SimpleBook.sourceUrl}/5.html');
      expect(nexts.containsKey('/5.html'), isTrue);
      expect(nexts['/5.html'], isNull);
    });
  });

  group('替换净化', () {
    testWidgets('打开章节时去掉广告', (tester) async {
      await services.addReplaceRules([{'id': 1, 'pattern': '第3章第1段'}]);
      await open(tester, startAt: 3);
      expect(paragraph(3, 0), findsOneWidget);
      expect(paragraph(3, 1), findsNothing);
      expect(paragraph(3, 2), findsOneWidget);
    });

    testWidgets('改规则后不用清缓存：重新打开按新规则显示，不请求网络，缓存里仍是原文', (tester) async {
      await open(tester, startAt: 3);
      expect(paragraph(3, 1), findsOneWidget);
      await back(tester);
      await services.addReplaceRules([{'id': 1, 'pattern': '第3章第1段'}]);
      services.engine.calls.clear();
      await open(tester, startAt: 3);
      expect(paragraph(3, 1), findsNothing);
      expect(services.engine.calls.where((call) => call.startsWith('content')), isEmpty);
      expect((await services.db.getContent(SimpleBook.bookUrl, '/3.html'))!.content, contains('第3章第1段'));
    });

    testWidgets('替换章节名：正文第一行替换后和章节名相同，章节名只显示一次', (tester) async {
      services.engine.onContent = (source, book, chapter, next) async =>
          ChapterContent('${chapter.title}（求月票）\n${chapter.title}第0段', title: '${chapter.title}（求月票）');
      await services.addReplaceRules([{'id': 1, 'pattern': '（求月票）', 'scopeTitle': true}]);
      await open(tester, startAt: 3);
      expect(pageText(tester), '第3章\n第3章第0段');
    });

    testWidgets('规则超时：章节照常显示，提示这条规则已停用', (tester) async {
      await services.addReplaceRules([{'id': 1, 'name': '回溯', 'pattern': r'(a+)+b'}]);
      services.engine.onReplace = (input, rule) => Future.error(TaskTimeoutException(rule.timeout));
      await open(tester, startAt: 3);
      expect(paragraph(3, 0), findsOneWidget);
      expect(find.text('替换规则「回溯」超时，已停用'), findsOneWidget);
      expect(services.replaceRules.isEnabled(1), isFalse);
    });
  });

  group('屏幕常亮', () {
    testWidgets('设置关闭时不常亮；在阅读页里打开、关闭立即生效', (tester) async {
      await open(tester, startAt: 0);
      expect(services.screen.calls, isEmpty);
      await update(tester, (s) => s.copyWith(keepScreenOn: true));
      expect(services.screen.calls, [true]);
      await update(tester, (s) => s.copyWith(keepScreenOn: false));
      expect(services.screen.calls, [true, false]);
      await back(tester);
      expect(services.screen.calls, [true, false]);
    });

    testWidgets('打开时进入阅读页常亮，app 退到后台恢复、回到前台再常亮，返回后恢复', (tester) async {
      await open(tester, startAt: 0);
      await update(tester, (s) => s.copyWith(keepScreenOn: true));
      await back(tester);
      services.screen.calls.clear();

      await open(tester, startAt: 0);
      expect(services.screen.calls, [true]);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(services.screen.calls, [true, false]);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(services.screen.calls, [true, false, true]);
      await back(tester);
      expect(services.screen.calls, [true, false, true, false]);
    });
  });

  group('音量键翻页', () {
    const android = TargetPlatformVariant({TargetPlatform.android});
    const down = LogicalKeyboardKey.audioVolumeDown, up = LogicalKeyboardKey.audioVolumeUp;

    /// 按一下：返回这次按下有没有被阅读页消费（没消费的交回系统调音量）。
    Future<bool> press(WidgetTester tester, LogicalKeyboardKey key) async {
      final handled = await simulateKeyDownEvent(key, platform: 'android');
      await simulateKeyUpEvent(key, platform: 'android');
      await tester.pumpAndSettle();
      return handled;
    }

    testWidgets('音量减翻到下一页，音量加翻回来，按键被消费', (tester) async {
      await open(tester, startAt: 3);
      final first = pageText(tester);
      await tapRight(tester);
      final second = pageText(tester);
      await tapLeft(tester);
      expect(await press(tester, down), isTrue);
      expect(pageText(tester), second);
      expect(await press(tester, up), isTrue);
      expect(pageText(tester), first);
    }, variant: android);

    testWidgets('按住不放只翻一页', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      final second = pageText(tester);
      await tapLeft(tester);
      expect(await simulateKeyDownEvent(down, platform: 'android'), isTrue);
      for (var i = 0; i < 5; i++) {
        expect(await simulateKeyRepeatEvent(down, platform: 'android'), isTrue);
      }
      expect(await simulateKeyUpEvent(down, platform: 'android'), isTrue);
      await tester.pumpAndSettle();
      expect(pageText(tester), second);
    }, variant: android);

    testWidgets('滚动模式：音量减向下滚一屏，音量加滚回来', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      double pixels() => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      final start = pixels();
      expect(await press(tester, down), isTrue);
      expect(pixels(), greaterThan(start + 300));
      expect(await press(tester, up), isTrue);
      expect(pixels(), closeTo(start, 1));
    }, variant: android);

    testWidgets('菜单显示时不翻页，按键交回系统', (tester) async {
      await open(tester, startAt: 3);
      final first = pageText(tester);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      expect(await press(tester, down), isFalse);
      expect(pageText(tester), first);
    }, variant: android);

    testWidgets('设置关闭时不翻页，按键交回系统', (tester) async {
      await open(tester, startAt: 3);
      await update(tester, (s) => s.copyWith(volumeKeyTurn: false));
      final first = pageText(tester);
      expect(await press(tester, down), isFalse);
      expect(pageText(tester), first);
    }, variant: android);

    testWidgets('不是 Android 时不处理', (tester) async {
      await open(tester, startAt: 3);
      expect(await press(tester, down), isFalse);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('打开再关掉设置面板、目录以后，音量键照样翻页', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      final second = pageText(tester);
      await tapLeft(tester);
      // 设置面板
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(await press(tester, down), isFalse, reason: '面板打开时交回系统');
      Navigator.of(tester.element(find.text('跟随系统深色'))).pop();
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage))); // 隐藏菜单
      await tester.pumpAndSettle();
      expect(await press(tester, down), isTrue);
      expect(pageText(tester), second);
      await press(tester, up);
      // 目录
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      expect(await press(tester, down), isFalse, reason: '目录打开时交回系统');
      Navigator.of(tester.element(find.byType(Drawer))).pop();
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      expect(await press(tester, down), isTrue);
      expect(pageText(tester), second);
    }, variant: android);
  });

  group('分页：章节之间连续翻页', () {
    testWidgets('翻进下一章：显示第 4 章第 1 页，菜单里的章节名变成第 4 章', (tester) async {
      await open(tester, startAt: 3);
      await turnUntil(tester, paragraph(4, 0));
      expect(pageText(tester), startsWith('第4章'));
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('第4章')), findsOneWidget);
    });

    testWidgets('往回翻到上一章的末页；往前翻也不等待，不请求网络', (tester) async {
      await open(tester, startAt: 4);
      services.engine.calls.clear();
      await tapLeft(tester);
      expect(paragraph(3, 59), findsOneWidget);
      // 第 3 章早就预加载过；翻进去以后窗口开始预加载新的上一章（第 2 章）
      expect(services.engine.calls, isNot(contains('content /3.html')));
    });

    testWidgets('下一章还没加载好：先显示加载中的页，正文返回后显示下一章第 1 页', (tester) async {
      final pending = Completer<void>();
      final original = services.engine.onContent!;
      services.engine.onContent = (source, book, chapter, next) async {
        if (chapter.url == '/4.html') await pending.future;
        return original(source, book, chapter, next);
      };
      await open(tester, startAt: 3);
      for (var i = 0; i < 30 && find.byType(CircularProgressIndicator).evaluate().isEmpty; i++) {
        await tester.tapAt(Offset(tester.getSize(find.byType(ReaderPage)).width - 20, 300));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(paragraph(4, 0), findsOneWidget);
      expect(pageText(tester), startsWith('第4章'));
    });

    testWidgets('读完直接进下一章：预加载过的下一章用菜单打开，不再请求', (tester) async {
      await open(tester, startAt: 3);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '下一章'));
      await tester.pumpAndSettle();
      expect(paragraph(4, 0), findsOneWidget);
      expect(services.engine.calls.where((c) => c == 'content /4.html'), hasLength(1));
    });

    testWidgets('分页模式用菜单换章：在第 3 章第 3 页点下一章，显示第 4 章第 1 页', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      await tapRight(tester);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '下一章'));
      await tester.pumpAndSettle();
      expect(pageText(tester), startsWith('第4章'), reason: '第 1 页顶部是章节名');
    });

    testWidgets('上一章、下一章跳过卷：从第 1 章翻过去是第 3 章', (tester) async {
      final shelved = await services.db.chaptersOf(SimpleBook.bookUrl);
      await services.db.saveBrowsingBook((await services.db.getBook(SimpleBook.bookUrl))!, [
        for (final c in shelved) c.idx == 2 ? c.copyWith(isVolume: true, title: '第二卷', url: '第二卷2') : c,
      ]);
      await open(tester, startAt: 1);
      await turnUntil(tester, paragraph(3, 0));
      expect(services.engine.calls.where((c) => c.contains('第二卷')), isEmpty);
    });

    testWidgets('已是最后一章：最后一页往后翻，页面不动，提示已是最后一章', (tester) async {
      await open(tester, startAt: 5);
      await turnUntil(tester, paragraph(5, 59));
      final before = pageText(tester);
      await tester.tapAt(Offset(tester.getSize(find.byType(ReaderPage)).width - 20, 300));
      await tester.pump();
      expect(find.text('已是最后一章'), findsOneWidget);
      expect(pageText(tester), before);
    });
  });

  group('菜单', () {
    testWidgets('点正文中间显示菜单，目录里标出当前章节，点击跳转；再点中间隐藏', (tester) async {
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

    testWidgets('菜单打开时点右侧：菜单隐藏，页面不翻', (tester) async {
      await open(tester, startAt: 3);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      final before = pageText(tester);
      await tapRight(tester);
      expect(find.byTooltip('目录'), findsNothing);
      expect(pageText(tester), before);
    });
  });

  group('滚动模式', () {
    testWidgets('预加载的下一章直接显示，不再请求', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      await tester.scrollUntilVisible(find.text('下一章'), 500);
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(paragraph(4, 0), findsOneWidget);
      expect(services.engine.calls.where((c) => c == 'content /4.html'), hasLength(1));
    });

    testWidgets('下一章停在章首；最后一章显示已是最后一章', (tester) async {
      await open(tester, startAt: 4);
      await useScroll(tester);
      expect(find.text('上一章'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('下一章'), 500);
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('第5章'), findsOneWidget);
      expect(topOf(tester, paragraph(5, 0)), lessThan(200));
      await tester.scrollUntilVisible(find.text('已是最后一章'), 500);
      expect(find.text('下一章'), findsNothing);
    });

    testWidgets('上一章、下一章跳过卷', (tester) async {
      final shelved = await services.db.chaptersOf(SimpleBook.bookUrl);
      await services.db.saveBrowsingBook((await services.db.getBook(SimpleBook.bookUrl))!, [
        for (final c in shelved) c.idx == 2 ? c.copyWith(isVolume: true, title: '第二卷', url: '第二卷2') : c,
      ]);
      await open(tester, startAt: 1);
      await useScroll(tester);
      await tester.scrollUntilVisible(find.text('下一章'), 500);
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(paragraph(3, 0), findsOneWidget);
      await tester.tap(find.text('上一章'));
      await tester.pumpAndSettle();
      expect(paragraph(1, 0), findsOneWidget);
    });

    testWidgets('点下方三分之一向下滚动大约一屏，点上方滚回来', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      await tester.tapAt(Offset(400, position.viewportDimension - 20));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(position.viewportDimension - 18 * 1.8, 1));
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
    });

    testWidgets('调大字号后，原来顶部那一行仍在顶部', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      await scrollTo(tester, paragraph(3, 20));
      await update(tester, (s) => s.copyWith(fontSize: 24));
      expect(topOf(tester, paragraph(3, 20)), closeTo(0, 1));
    });

    testWidgets('一章 300 段，进度在第 250 段：打开后这一段在顶部', (tester) async {
      await services.useSimpleBook(chapters: 6, paragraphs: 300);
      final offset = [for (var p = 0; p < 250; p++) '第0章第$p段'.length + 1].reduce((a, b) => a + b);
      await services.db.saveProgress(SimpleBook.bookUrl, index: 0, url: '/0.html', title: '第0章', position: offset, now: DateTime(2026));
      await open(tester);
      await useScroll(tester);
      expect(topOf(tester, paragraph(0, 250)), closeTo(0, 1));
    });
  });

  group('设置', () {
    testWidgets('调大字号不丢位置：重新分页，显示的这一页包含原来那页的首字', (tester) async {
      await open(tester, startAt: 3);
      for (var i = 0; i < 3; i++) {
        await tapRight(tester);
      }
      final first = firstParagraph(tester);
      await update(tester, (s) => s.copyWith(fontSize: 24));
      expect(pageText(tester), contains(first));
    });

    /// 分页视图当前画的这一页。
    PagePainter painterOf(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.descendant(of: find.byType(PagedView), matching: find.byType(CustomPaint)))
        .map((paint) => paint.painter)
        .whereType<PagePainter>()
        .last;

    testWidgets('调大段距不丢位置：重新分页，显示的这一页包含原来那页的首字', (tester) async {
      await open(tester, startAt: 3);
      for (var i = 0; i < 3; i++) {
        await tapRight(tester);
      }
      final first = firstParagraph(tester);
      await update(tester, (s) => s.copyWith(paragraphSpacing: 1.2));
      expect(painterOf(tester).layout.spec.paragraphSpacing, closeTo(18 * 1.2, 0.001));
      expect(pageText(tester), contains(first));
    });

    testWidgets('调大左右边距：正文、页眉页脚离两边 40，正文变窄 40，不丢位置', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      await tapRight(tester);
      final first = firstParagraph(tester);
      final before = painterOf(tester).layout.spec.size.width;
      await update(tester, (s) => s.copyWith(margin: 40));
      final painter = painterOf(tester);
      expect((painter.insets.left, painter.insets.right), (40, 40));
      expect(painter.layout.spec.size.width, before - 40);
      expect(pageText(tester), contains(first));
    });

    testWidgets('首行缩进调成 0：排版参数里的缩进是 0', (tester) async {
      await open(tester, startAt: 3);
      await update(tester, (s) => s.copyWith(indent: 0));
      expect(painterOf(tester).layout.spec.indent, 0);
    });

    testWidgets('滚动模式用设置的左右边距：段落离左边 40', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      await update(tester, (s) => s.copyWith(margin: 40));
      expect(tester.getTopLeft(paragraph(3, 0)).dx, 40);
    });

    testWidgets('切换翻页方式不丢位置：滚动模式顶部那一行，切到覆盖后在显示的这一页里', (tester) async {
      await open(tester, startAt: 3);
      await useScroll(tester);
      await scrollTo(tester, paragraph(3, 20));
      await update(tester, (s) => s.copyWith(pageMode: PageMode.cover));
      expect(paragraph(3, 20), findsOneWidget);
    });

    testWidgets('窗口尺寸改变后重新分页：每页的行数变多，仍显示包含原来那页首字的页', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      await tapRight(tester);
      final first = firstParagraph(tester);
      final lines = pageText(tester).split('\n').length;
      tester.view.physicalSize = tester.view.physicalSize + const Offset(0, 900);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(pageText(tester), contains(first));
      expect(pageText(tester).split('\n').length, greaterThan(lines));
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

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
    }

    testWidgets('设置面板：段距、缩进、边距拖到最右，打开屏幕常亮、关掉音量键翻页，都落盘', (tester) async {
      await open(tester, startAt: 0);
      await openSettings(tester);
      for (final label in ['段距', '缩进', '边距']) {
        final slider = find.byWidgetPredicate((widget) => widget is Slider && widget.label == label);
        await tester.drag(slider, const Offset(1000, 0));
        await tester.pumpAndSettle();
      }
      for (final title in ['屏幕常亮', '音量键翻页']) {
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      final saved = await services.db.loadSettings();
      expect(
        [for (final key in ['paragraphSpacing', 'indent', 'margin', 'keepScreenOn', 'volumeKeyTurn']) saved['reader.$key']],
        ['2.0', '4', '48.0', 'true', 'false'],
      );
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));

    testWidgets('「音量键翻页」只在 Android 上显示', (tester) async {
      await open(tester, startAt: 0);
      await openSettings(tester);
      await tester.ensureVisible(find.text('屏幕常亮'));
      await tester.pumpAndSettle();
      expect(find.text('音量键翻页'), defaultTargetPlatform == TargetPlatform.android ? findsOneWidget : findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

    testWidgets('设置面板切换翻页方式和跟随系统深色，落盘', (tester) async {
      await open(tester, startAt: 0);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('滚动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统深色'));
      await tester.pumpAndSettle();
      final saved = await services.db.loadSettings();
      expect((saved['reader.pageMode'], saved['reader.followSystemDark']), ('scroll', 'false'));
    });

    testWidgets('状态栏图标的深浅跟着正文背景：暗主题用浅色图标，亮、护眼用深色', (tester) async {
      await open(tester, startAt: 0);
      Brightness? icons() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.descendant(of: find.byType(ReaderPage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
          )
          .value
          .statusBarIconBrightness;
      expect(icons(), Brightness.dark);
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      for (final (theme, expected) in [(ReaderTheme.dark, Brightness.light), (ReaderTheme.sepia, Brightness.dark)]) {
        await tester.tap(find.text(theme.label));
        await tester.pumpAndSettle();
        expect(icons(), expected, reason: theme.label);
      }
    });

    Color background(WidgetTester tester) =>
        tester.widget<Scaffold>(find.descendant(of: find.byType(ReaderPage), matching: find.byType(Scaffold)).first).backgroundColor!;

    testWidgets('系统切到深色：变成暗主题，还停在原来那一页；切回浅色恢复护眼主题', (tester) async {
      await open(tester, startAt: 3);
      await update(tester, (s) => s.copyWith(theme: ReaderTheme.sepia));
      await tapRight(tester);
      final before = pageText(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(background(tester), ReaderTheme.dark.background);
      expect(pageText(tester), before);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(background(tester), ReaderTheme.sepia.background);
    });

    testWidgets('关闭跟随：系统是深色时仍用选的亮主题', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await open(tester, startAt: 0);
      expect(background(tester), ReaderTheme.dark.background);
      await update(tester, (s) => s.copyWith(followSystemDark: false));
      expect(background(tester), ReaderTheme.light.background);
    });
  });

  group('进度', () {
    testWidgets('换屏幕尺寸后定位：读到第 5 章第 4 页，窗口拉宽后重新打开，显示的这一页包含原来第 4 页的首字', (tester) async {
      await open(tester, startAt: 5);
      for (var i = 0; i < 3; i++) {
        await tapRight(tester);
      }
      final first = firstParagraph(tester);
      await back(tester);
      final book = (await services.db.getBook(SimpleBook.bookUrl))!;
      expect((book.durChapterIndex, book.durChapterUrl, book.durChapterTitle), (5, '/5.html', '第5章'));
      expect(book.durChapterPos, greaterThan(0));
      expect(book.lastReadAt, isNotNull);

      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      await open(tester);
      expect(pageText(tester), contains(first));
    });

    testWidgets('翻进新章节后立刻离开：再次打开回到第 4 章第 1 页', (tester) async {
      await open(tester, startAt: 3);
      await turnUntil(tester, paragraph(4, 0));
      await back(tester);
      final book = (await services.db.getBook(SimpleBook.bookUrl))!;
      expect((book.durChapterIndex, book.durChapterPos), (4, 0));
      await open(tester);
      expect(pageText(tester), startsWith('第4章'));
    });

    testWidgets('翻页后 2 秒内没有再翻时保存', (tester) async {
      await open(tester, startAt: 3);
      await tapRight(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterPos, greaterThan(0));
    });

    testWidgets('滚动模式：离开时保存顶部那一行；换了窗口尺寸重新打开，这一行回到顶部', (tester) async {
      await open(tester, startAt: 5);
      await useScroll(tester);
      await scrollTo(tester, paragraph(5, 30));
      await back(tester);
      expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterPos, greaterThan(0));
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      await open(tester);
      expect(topOf(tester, paragraph(5, 30)), closeTo(0, 1));
    });

    testWidgets('重启后从书架进入，回到上次的章节和页，缓存的正文不再请求', (tester) async {
      final dir = Directory.systemTemp.createTempSync('reader');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      var app = await TestServices.create(file: file);
      await app.useSimpleBook(chapters: 6, paragraphs: 60);
      await app.shelveSimpleBook(chapters: 6);
      await open(tester, startAt: 4, using: app);
      await tapRight(tester);
      await tapRight(tester);
      final first = firstParagraph(tester);
      await back(tester);
      await tester.pumpWidget(const SizedBox());
      await app.db.close();

      app = await TestServices.create(file: file);
      await app.useSimpleBook(chapters: 6, paragraphs: 60);
      await app.db.purgeBrowsingBooks();
      expect((await app.db.shelf()).single.book.bookUrl, SimpleBook.bookUrl);
      app.engine.calls.clear();
      await open(tester, using: app);
      expect(firstParagraph(tester), first);
      expect(app.engine.calls.where((c) => c == 'content /4.html'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await app.db.close();
    });
  });
}
