import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/chapter_format.dart';
import 'package:novel_reader/reader/layout/chapter_layout.dart';
import 'package:novel_reader/reader/layout/page_painter.dart';
import 'package:novel_reader/reader/reader_settings.dart';

/// 手机尺寸的一页，安全区上下各留一点。golden 用测试字体（每个字都是方块）。
const _page = Size(360, 640);
const _safeArea = EdgeInsets.only(top: 24, bottom: 16);

const _filler = '山风从谷底卷上来吹得崖边的松枝簌簌作响他站在最高的那块石头上望着远处渐渐亮起来的天色';

ChapterLayout _layout(FormattedChapter chapter, {bool isVolume = false, bool complete = true}) {
  final insets = PageGeometry.bodyInsets(_safeArea);
  final layout = ChapterLayout(chapter, LayoutSpec(fontSize: 18, lineHeight: 1.8, size: insets.deflateSize(_page)), isVolume: isVolume);
  layout.layoutThrough(complete ? 1 << 30 : 0);
  return layout;
}

FormattedChapter _chapter() =>
    formatChapter('第三章 下山', [for (var i = 0; i < 40; i++) '${_filler.substring(0, 6 + (i * 11) % (_filler.length - 6))}。'].join('\n'));

Future<void> _pumpPage(WidgetTester tester, ChapterLayout layout, int index) async {
  tester.view.physicalSize = _page;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        child: CustomPaint(
          size: _page,
          painter: PagePainter(layout: layout, index: index, theme: ReaderTheme.sepia, insets: PageGeometry.bodyInsets(_safeArea)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('章首页：页眉、章节名、正文、页脚', (tester) async {
    final layout = _layout(_chapter());
    await _pumpPage(tester, layout, 0);
    await expectLater(find.byType(RepaintBoundary), matchesGoldenFile('goldens/page_first.png'));
    layout.dispose();
  });

  testWidgets('中间的页：顶部和底部都是跨页的段落', (tester) async {
    final layout = _layout(_chapter());
    final index = layout.pages.indexWhere(
      (page) => page.segments.first.from > 0 && page.segments.last.to < layout.linesOf(page.segments.last.paragraph).lines.length,
    );
    expect(index, greaterThan(0), reason: '这组段落应该有上下都跨页的一页');
    await _pumpPage(tester, layout, index);
    await expectLater(find.byType(RepaintBoundary), matchesGoldenFile('goldens/page_split.png'));
    layout.dispose();
  });

  testWidgets('卷页：只有卷名，在正文区域中间', (tester) async {
    final layout = _layout((title: '第二卷 江湖', paragraphs: const []), isVolume: true);
    await _pumpPage(tester, layout, 0);
    await expectLater(find.byType(RepaintBoundary), matchesGoldenFile('goldens/page_volume.png'));
    layout.dispose();
  });

  test('页脚：排完时是「页码/总页数」，没排完时只有页码', () {
    final partial = _layout(_chapter(), complete: false);
    expect(partial.complete, isFalse);
    expect(pageFooter(partial, 0), '1');
    final complete = _layout(_chapter());
    expect(pageFooter(complete, 4), '5/${complete.pages.length}');
    partial.dispose();
    complete.dispose();
  });

  testWidgets('本章排完时页面重画，页脚补上总页数', (tester) async {
    final layout = _layout(_chapter(), complete: false);
    await _pumpPage(tester, layout, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    layout.layoutSlice(const Duration(days: 1));
    // PagePainter 监听 layout：排完时页面被标脏，调度了新的一帧
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(pageFooter(layout, 0), '1/${layout.pages.length}');
    layout.dispose();
  });
}
