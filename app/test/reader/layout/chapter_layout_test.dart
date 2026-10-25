import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/chapter_format.dart';
import 'package:novel_reader/reader/layout/chapter_layout.dart';

/// 测试字体里每个字都是一个字宽（18），正文宽 335 不是字宽的整数倍，避免每行正好排满。
const _spec = LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600));

const _filler = '山风从谷底卷上来吹得崖边的松枝簌簌作响他站在最高的那块石头上望着远处渐渐亮起来的天色';

/// [count] 段，长短不一：每段 [_filler] 的前若干个字，最后加句号。
FormattedChapter _chapter(int count, {String title = '第一章 开始'}) =>
    formatChapter(title, [for (var i = 0; i < count; i++) '${_filler.substring(0, 6 + (i * 7) % (_filler.length - 6))}。'].join('\n'));

List<TextBox> _boxes(TextPainter painter, int start, int end) =>
    painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));

void main() {
  group('3.1 段落排版', () {
    test('单行段落和多行段落首字的横坐标相同，都是两个字宽', () {
      final layout = ChapterLayout(formatChapter('t', '他点了点头。\n${_filler * 2}'), _spec);
      final xs = [
        for (final index in [0, 1])
          () {
            final lines = layout.linesOf(index).lines;
            final painter = layout.painterFor((paragraph: index, from: 0, to: lines.length, top: 0), const Color(0xFF000000));
            return painter.indent + _boxes(painter.first!, 0, 1).first.left;
          }(),
      ];
      expect(layout.linesOf(0).lines, hasLength(1));
      expect(layout.linesOf(1).lines.length, greaterThan(2));
      expect(xs, [36, 36]);
      layout.dispose();
    });

    test('首行缩进为 0 时，首字从左边缘开始', () {
      const spec = LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600), indentChars: 0);
      final layout = ChapterLayout(formatChapter('t', '他点了点头。'), spec);
      final painter = layout.painterFor((paragraph: 0, from: 0, to: 1, top: 0), const Color(0xFF000000));
      expect(painter.indent + _boxes(painter.first!, 0, 1).first.left, 0);
      layout.dispose();
    });

    test('段距 1.2 倍字号：同一页上相邻两段之间空出 21.6', () {
      const spec = LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600), paragraphSpacingRatio: 1.2);
      final layout = ChapterLayout(formatChapter('t', '第一段。\n第二段。'), spec)..layoutThrough(0);
      final [first, second] = layout.pages.single.segments;
      expect(second.top - (first.top + layout.linesOf(0).height), closeTo(21.6, 0.001));
      layout.dispose();
    });

    test('只有段距或缩进不同的两个排版参数不相等', () {
      expect(_spec, const LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600)));
      expect(_spec == const LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600), paragraphSpacingRatio: 1.2), isFalse);
      expect(_spec == const LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600), indentChars: 3), isFalse);
    });

    test('多行段落非末行贴齐右边缘，末行不拉伸', () {
      final text = '${_filler * 2}。';
      final layout = ChapterLayout(formatChapter('t', text), _spec);
      final lines = layout.linesOf(0).lines;
      final painter = layout.painterFor((paragraph: 0, from: 0, to: lines.length, top: 0), const Color(0xFF000000));
      final first = painter.first!, rest = painter.rest!;
      final firstEnd = layout.linesOf(0).firstEnd;
      // 首行：画的时候平移一个缩进，右边缘 = 缩进 + 首行 painter 里最后一个字的右边缘
      expect(painter.indent + _boxes(first, firstEnd - 1, firstEnd).last.right, closeTo(_spec.size.width, 0.01));
      for (final line in lines.sublist(1, lines.length - 1)) {
        final end = line.end - firstEnd;
        expect(_boxes(rest, end - 1, end).last.right, closeTo(_spec.size.width, 0.01));
      }
      // 末行：每个字还是一个字宽
      final last = lines.last;
      final boxes = _boxes(rest, last.start - firstEnd, last.end - firstEnd);
      expect(boxes.last.right - boxes.first.left, closeTo((last.end - last.start) * 18, 0.01));
      layout.dispose();
    });

    test('每行的字符区间首尾相接，正好覆盖整段，emoji 的代理对不被切开', () {
      final text = List.generate(40, (i) => i.isEven ? '笑😀' : '哭👨‍👩‍👧').join();
      final layout = ChapterLayout(formatChapter('t', text), _spec);
      final lines = layout.linesOf(0).lines;
      expect(lines.length, greaterThan(2));
      expect(lines.first.start, 0);
      expect(lines.last.end, text.length);
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].start, lines[i - 1].end);
        expect(text.codeUnitAt(lines[i].start) & 0xFC00, isNot(0xDC00), reason: '第 $i 行从代理对的后半开始');
      }
      layout.dispose();
    });

    test('每行高度一致（forceStrutHeight，引擎取整差不到 0.5），行盒首尾相接，加起来等于段落高度', () {
      final layout = ChapterLayout(formatChapter('t', _filler * 3), _spec);
      final paragraph = layout.linesOf(0);
      expect(paragraph.lines.map((line) => line.height), everyElement(closeTo(18 * 1.8, 0.5)));
      expect(paragraph.lines.first.top, 0);
      for (var i = 1; i < paragraph.lines.length; i++) {
        expect(paragraph.lines[i].top, closeTo(paragraph.lines[i - 1].top + paragraph.lines[i - 1].height, 0.001));
      }
      expect(paragraph.lines.fold(0.0, (sum, line) => sum + line.height), closeTo(paragraph.height, 0.01));
      layout.dispose();
    });
  });

  group('3.2 切页', () {
    ChapterLayout complete(FormattedChapter chapter, [LayoutSpec spec = _spec]) => ChapterLayout(chapter, spec)..layoutThrough(1 << 30);

    test('段落跨页：每段的行在各页里按顺序出现一次，不重不漏；每页不超高', () {
      final layout = complete(_chapter(80));
      final seen = <(int, int)>[];
      var split = 0;
      for (final page in layout.pages) {
        var bottom = 0.0;
        for (final s in page.segments) {
          final lines = layout.linesOf(s.paragraph).lines;
          for (var i = s.from; i < s.to; i++) {
            seen.add((s.paragraph, i));
          }
          if (s.from > 0) split++;
          bottom = s.top + lines[s.to - 1].top + lines[s.to - 1].height - lines[s.from].top;
        }
        expect(bottom, lessThanOrEqualTo(_spec.size.height + 0.01));
      }
      expect(seen, [
        for (var p = 0; p < 80; p++)
          for (var i = 0; i < layout.linesOf(p).lines.length; i++) (p, i),
      ]);
      expect(split, greaterThan(0), reason: '这组段落应该有跨页的');
      layout.dispose();
    });

    test('跨页处：后一页从这一段的下一行开始，页的起始偏移就是这一行的首字', () {
      final layout = complete(_chapter(80));
      for (var i = 1; i < layout.pages.length; i++) {
        final first = layout.pages[i].segments.first;
        final previous = layout.pages[i - 1].segments.last;
        if (first.from > 0) {
          expect((previous.paragraph, previous.to), (first.paragraph, first.from));
        }
        expect(layout.pages[i].start, layout.offsetOf(first.paragraph, first.from));
        expect(layout.pages[i].start, greaterThanOrEqualTo(layout.pages[i - 1].end));
      }
      layout.dispose();
    });

    test('章节名只在第一页', () {
      final layout = complete(_chapter(80));
      expect([for (final page in layout.pages) page.hasTitle], [true, for (var i = 1; i < layout.pages.length; i++) false]);
      expect(layout.pages.first.start, 0);
      layout.dispose();
    });

    test('卷和空章只有一页，只有章节名', () {
      for (final layout in [
        ChapterLayout((title: '第一卷', paragraphs: const []), _spec, isVolume: true),
        ChapterLayout(formatChapter('空章', ''), _spec),
      ]) {
        expect(layout.complete, isTrue);
        expect(layout.pages, hasLength(1));
        expect(layout.pages.single.hasTitle, isTrue);
        expect(layout.pages.single.segments, isEmpty);
        layout.dispose();
      }
    });

    test('字号极大、页面极小时，一行在空页上也放不下：每页强制放一行', () {
      const tiny = LayoutSpec(fontSize: 40, lineHeight: 1.8, size: Size(335, 30));
      final layout = complete(_chapter(5), tiny);
      final lineCount = [for (var p = 0; p < 5; p++) layout.linesOf(p).lines.length].reduce((a, b) => a + b);
      // 第一页只有章节名（第一行放不下，章节名所在的页不算空页）
      expect(layout.pages.first.segments, isEmpty);
      expect(layout.pages.skip(1).map((page) => page.segments.single.to - page.segments.single.from), everyElement(1));
      expect(layout.pages, hasLength(lineCount + 1));
      layout.dispose();
    });

    test('偏移二分查找：0、页首、页首前一个字、章末、超出章末', () {
      final layout = complete(_chapter(80));
      final pages = layout.pages;
      expect(layout.pageAt(0), 0);
      for (var i = 1; i < pages.length; i++) {
        expect(layout.pageAt(pages[i].start), i);
        expect(layout.pageAt(pages[i].start - 1), i - 1);
        expect(layout.pageAt(pages[i - 1].end - 1), i - 1);
      }
      expect(layout.pageAt(pages.last.end), pages.length - 1);
      expect(layout.pageAt(1 << 30), pages.length - 1);
      layout.dispose();
    });
  });

  group('3.3 增量排版', () {
    test('同步阶段只排到包含目标偏移的页再多一页', () {
      final reference = ChapterLayout(_chapter(80), _spec)..layoutThrough(1 << 30);
      final target = reference.pages[5].start + 3;
      final layout = ChapterLayout(_chapter(80), _spec)..layoutThrough(target);
      expect(layout.complete, isFalse);
      expect(layout.pages, hasLength(7));
      expect(layout.pageAt(target), 5);
      reference.dispose();
      layout.dispose();
    });

    test('分帧阶段每批不超过预算；排完后和一次排完的结果相同', () {
      var now = Duration.zero;
      // 每问一次时间过去 1ms：一批 4ms 的预算最多排 3 段
      final layout = ChapterLayout(_chapter(80), _spec, clock: () => now += const Duration(milliseconds: 1));
      final tasks = <void Function()>[];
      layout.layoutThrough(0);
      layout.layoutInBackground(tasks.add);
      var placed = layout.debugPlacedParagraphs;
      while (tasks.isNotEmpty) {
        tasks.removeAt(0)();
        expect(layout.debugPlacedParagraphs - placed, lessThanOrEqualTo(3));
        placed = layout.debugPlacedParagraphs;
      }
      expect(layout.complete, isTrue);
      final reference = ChapterLayout(_chapter(80), _spec)..layoutThrough(1 << 30);
      expect([for (final page in layout.pages) (page.start, page.end)], [for (final page in reference.pages) (page.start, page.end)]);
      layout.dispose();
      reference.dispose();
    });

    test('换代以后，旧一代还没执行的任务不再改动结果', () {
      final tasks = <void Function()>[];
      final old = ChapterLayout(_chapter(80), _spec)..layoutThrough(0);
      old.layoutInBackground(tasks.add);
      final pages = old.pages.length;
      old.dispose();
      while (tasks.isNotEmpty) {
        tasks.removeAt(0)();
      }
      expect(old.pages, hasLength(pages));
      expect(old.complete, isFalse);
    });

    test('排出新的页时通知监听者', () {
      final layout = ChapterLayout(_chapter(80), _spec);
      var notified = 0;
      layout.addListener(() => notified++);
      layout.layoutThrough(0);
      expect(notified, 1);
      layout.layoutSlice(const Duration(days: 1));
      expect(notified, 2);
      expect(layout.complete, isTrue);
      layout.dispose();
    });
  });

  group('3.4 painter 生命周期', () {
    const color = Color(0xFF000000);

    void paintPage(ChapterLayout layout, int index) {
      final page = layout.pages[index];
      if (page.hasTitle) layout.titlePainter(color);
      for (final segment in page.segments) {
        layout.painterFor(segment, color);
      }
      layout.retainAround(index);
    }

    int bound(ChapterLayout layout, int index) {
      var count = 0;
      for (var i = (index - 2).clamp(0, layout.pages.length); i < (index + 3).clamp(0, layout.pages.length); i++) {
        count += layout.pages[i].segments.length + (layout.pages[i].hasTitle ? 1 : 0);
      }
      return count;
    }

    test('翻过 50 页后，存活的 painter 不超过前后各两页用到的数量；创建减释放等于存活', () {
      final layout = ChapterLayout(_chapter(1000), _spec)..layoutThrough(1 << 30);
      expect(layout.pages.length, greaterThan(50));
      for (var i = 0; i < 50; i++) {
        paintPage(layout, i);
        expect(layout.debugLivePainters, lessThanOrEqualTo(bound(layout, i)));
      }
      expect(layout.debugPaintersCreated - layout.debugPaintersDisposed, layout.debugLivePainters);
      layout.dispose();
      expect(layout.debugPaintersCreated, layout.debugPaintersDisposed);
    });

    test('释放后重新创建的 painter，断行和第一次量的一致（整段和页内 painter 都是）', () {
      final layout = ChapterLayout(_chapter(80), _spec)..layoutThrough(1 << 30);
      final page = layout.pages.indexWhere((page) => page.segments.first.from > 0);
      final segment = layout.pages[page].segments.first;
      layout.painterFor(segment, color);
      layout.retainAround(page + 10);
      final painter = layout.painterFor(segment, color);
      final lines = layout.linesOf(segment.paragraph);
      // 页内 painter 不含首行，只排了其余行；逐行比较区间
      final rest = painter.rest!;
      var offset = 0;
      for (final line in lines.lines.sublist(1)) {
        expect(rest.getLineBoundary(TextPosition(offset: offset)).start + lines.firstEnd, line.start);
        offset = line.end - lines.firstEnd;
      }
      expect(painter.first, isNull, reason: '首行不在这一页，不用排');
      layout.dispose();
    });

    test('换了颜色，旧颜色的 painter 全部释放', () {
      final layout = ChapterLayout(_chapter(10), _spec)..layoutThrough(1 << 30);
      paintPage(layout, 0);
      final live = layout.debugLivePainters;
      layout.painterFor(layout.pages[0].segments.first, const Color(0xFFFFFFFF));
      expect(layout.debugPaintersDisposed, live);
      expect(layout.debugLivePainters, 1);
      layout.dispose();
    });
  });
}
