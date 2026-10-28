import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/chapter_format.dart';
import 'package:novel_reader/reader/layout/chapter_layout.dart';
import 'package:novel_reader/reader/layout/page_painter.dart';
import 'package:novel_reader/reader/paged/chapter_window.dart';
import 'package:novel_reader/reader/paged/paged_view.dart';
import 'package:novel_reader/reader/reader_settings.dart';

import '../../support/fixtures.dart' as fixtures;

const _screen = Size(400, 800);

FormattedChapter _content(int index) =>
    formatChapter('第$index章', [for (var p = 0; p < 30; p++) '第$index章第$p段，山风从谷底卷上来，吹得崖边的松枝簌簌作响。'].join('\n'));

void main() {
  late ChapterWindow window;
  late ValueNotifier<bool> menu;
  final insets = PageGeometry.bodyInsets(EdgeInsets.zero, 20);

  /// 打开第 [chapter] 章（正文立即返回、排版全部完成），显示分页视图。
  Future<void> pumpView(WidgetTester tester, PageMode mode, {int chapter = 3}) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = <VoidCallback>[];
    window = ChapterWindow(
      chapters: [for (var i = 0; i < 8; i++) fixtures.chapter('b', i)],
      load: (index) async => _content(index),
      spec: LayoutSpec(fontSize: 18, lineHeight: 1.8, size: insets.deflateSize(_screen)),
      schedule: tasks.add,
    );
    menu = ValueNotifier(false);
    addTearDown(window.dispose);
    window.open(chapter);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    while (tasks.isNotEmpty) {
      tasks.removeAt(0)();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedView(window: window, mode: mode, theme: ReaderTheme.light, insets: insets, menu: menu),
        ),
      ),
    );
  }

  Finder page(int chapter, int index) => find.byKey(ValueKey<WindowPage>(TextPage(chapter, index)));

  double x(WidgetTester tester, Finder finder) => tester.widget<Transform>(finder).transform.getTranslation().x;

  Future<void> tapRight(WidgetTester tester) => tester.tapAt(const Offset(350, 400));

  group('两页摆放与动画', () {
    for (final mode in [PageMode.cover, PageMode.slide]) {
      testWidgets('${mode.label}：点右侧，动画过程中两页的位置符合公式，结束时显示下一页', (tester) async {
        await pumpView(tester, mode);
        await tapRight(tester);
        await tester.pump();
        await tester.pump(PagedView.turnDuration ~/ 2);
        final t = PagedView.turnCurve.transform(0.5);
        expect(x(tester, page(3, 0)), (-t * _screen.width).roundToDouble());
        expect(x(tester, page(3, 1)), mode == PageMode.slide ? ((1 - t) * _screen.width).roundToDouble() : 0);
        await tester.pumpAndSettle();
        expect(window.current, const TextPage(3, 1));
        expect(page(3, 0), findsNothing);
        expect(x(tester, page(3, 1)), 0);
      });
    }

    testWidgets('无动画：点右侧立即显示下一页，没有过渡', (tester) async {
      await pumpView(tester, PageMode.none);
      await tapRight(tester);
      await tester.pump();
      expect(window.current, const TextPage(3, 1));
      expect(page(3, 0), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('动画进行中再点一次：先完成这一次，再开始下一次，最终前进两页', (tester) async {
      await pumpView(tester, PageMode.slide);
      await tapRight(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tapRight(tester);
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 2));
    });

    testWidgets('覆盖：往前翻时上一页从左边盖上来', (tester) async {
      await pumpView(tester, PageMode.cover);
      window.moveTo(const TextPage(3, 2));
      await tester.pump();
      await tester.tapAt(const Offset(50, 400));
      await tester.pump();
      await tester.pump(PagedView.turnDuration ~/ 2);
      final t = PagedView.turnCurve.transform(0.5);
      expect(x(tester, page(3, 1)), (-(1 - t) * _screen.width).roundToDouble());
      expect(x(tester, page(3, 2)), 0);
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 1));
    });
  });

  group('拖动', () {
    testWidgets('快速轻扫翻页：向左快速一甩，手指只移动了一小段', (tester) async {
      await pumpView(tester, PageMode.cover);
      // 40ms 内移动 60：每秒 1500，拖过的距离只有页宽的一成多
      await tester.timedDragFrom(const Offset(300, 400), const Offset(-60, 0), const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 1));
    });

    testWidgets('拖一点就松手：慢慢拖五分之一屏宽后停住松手，回到原页', (tester) async {
      await pumpView(tester, PageMode.slide);
      final gesture = await tester.startGesture(const Offset(300, 400));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 页面跟着手指往左走；起拖距离（18）那一段不算位移
      expect(x(tester, page(3, 0)), inExclusiveRange(-80, 0));
      // 停住一会儿再松手，速度为零
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 0));
    });

    testWidgets('拖过去又甩回来：向左拖过半屏，再向右快速一甩，回到原页', (tester) async {
      await pumpView(tester, PageMode.slide);
      final gesture = await tester.startGesture(const Offset(380, 400));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 0));
    });

    testWidgets('无动画：拖动时页面不动，松手按同样的规则换页', (tester) async {
      await pumpView(tester, PageMode.none);
      final gesture = await tester.startGesture(const Offset(380, 400));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(x(tester, page(3, 0)), 0);
      expect(page(3, 1), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();
      expect(window.current, const TextPage(3, 1));
    });
  });

  group('点击区域', () {
    testWidgets('点右侧翻到下一页，点左侧翻回上一页，点中间显示菜单', (tester) async {
      await pumpView(tester, PageMode.cover);
      await tapRight(tester);
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 1));
      await tester.tapAt(const Offset(50, 400));
      await tester.pumpAndSettle();
      expect(window.current, const TextPage(3, 0));
      await tester.tapAt(const Offset(200, 400));
      expect(menu.value, isTrue);
    });

    testWidgets('菜单打开时点右侧：菜单隐藏，页面不翻', (tester) async {
      await pumpView(tester, PageMode.cover);
      menu.value = true;
      await tapRight(tester);
      await tester.pumpAndSettle();
      expect(menu.value, isFalse);
      expect(window.current, const TextPage(3, 0));
    });

    testWidgets('已是最后一章：往后拖页面不动，提示已是最后一章', (tester) async {
      await pumpView(tester, PageMode.cover, chapter: 7);
      final last = window.layoutOf(7)!.pages.length - 1;
      window.moveTo(TextPage(7, last));
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(380, 400));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(x(tester, page(7, last)), 0);
      await gesture.up();
      await tester.pump();
      expect(find.text('已是最后一章'), findsOneWidget);
      expect(window.current, TextPage(7, last));
    });

    testWidgets('已是第一章：点左侧不翻页，提示已是第一章', (tester) async {
      await pumpView(tester, PageMode.slide, chapter: 0);
      await tester.tapAt(const Offset(50, 400));
      await tester.pump();
      expect(find.text('已是第一章'), findsOneWidget);
      expect(window.current, const TextPage(0, 0));
    });
  });
}
