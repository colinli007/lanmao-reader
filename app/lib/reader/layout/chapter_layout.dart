import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../chapter_format.dart';

/// 排版参数：字号、行距、段距、首行缩进和正文区域的尺寸。任何一项变了，排版结果都作废，换一个新的 [ChapterLayout]（设计 D6）。
/// 段距和缩进相对字号给出，缺省是阅读设置的默认值（complete-reader-settings 设计 D2）。
@immutable
final class LayoutSpec {
  const LayoutSpec({
    required this.fontSize,
    required this.lineHeight,
    required this.size,
    this.paragraphSpacingRatio = 0.6,
    this.indentChars = 2,
  });

  final double fontSize;
  final double lineHeight;

  /// 正文区域：屏幕去掉安全区、页眉页脚和左右边距（设计 D15）。滚动模式只用宽度。
  final Size size;

  /// 段距是字号的几倍，首行缩进几个字。
  final double paragraphSpacingRatio;
  final int indentChars;

  /// 段首缩进（设计 D4）。
  double get indent => fontSize * indentChars;

  /// 段距（设计 D5）。
  double get paragraphSpacing => fontSize * paragraphSpacingRatio;

  @override
  bool operator ==(Object other) =>
      other is LayoutSpec &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.size == size &&
      other.paragraphSpacingRatio == paragraphSpacingRatio &&
      other.indentChars == indentChars;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight, size, paragraphSpacingRatio, indentChars);
}

/// 段内的一行：字符区间 [start, end)（相对段首），相对段落顶部的 [top] 和高度。
typedef Line = ({int start, int end, double top, double height});

/// 一段的排版数据（设计 D4）：首行单独排，[firstEnd] 是首行结束的位置；之后的行按正文宽度排。
typedef ParagraphLines = ({List<Line> lines, int firstEnd, double height});

/// 页里的一段：第 [paragraph] 段的第 [from] 到 [to]（不含）行，第一行的顶部在页内 [top] 处。
typedef Segment = ({int paragraph, int from, int to, double top});

/// 一页（设计 D5）。[start] 是这一页首字在本章里的偏移（D13），[end] 是最后一行结束的偏移。
/// [hasTitle] 的页顶部画章节名，只有第一页是。
@immutable
final class ChapterPage {
  const ChapterPage({required this.segments, required this.hasTitle, required this.start, required this.end});

  final List<Segment> segments;
  final bool hasTitle;
  final int start;
  final int end;
}

/// 分帧排版的调度：把一个任务排到之后执行。测试里换成手动执行的假调度器。
typedef LayoutScheduler = void Function(VoidCallback task);

/// 默认的调度：在下一帧开始时执行（会请求一帧）。每帧排一批，没排完就再请求下一帧，排完以后不再请求。
void scheduleNextFrame(VoidCallback task) => SchedulerBinding.instance.scheduleFrameCallback((_) => task());

final Stopwatch _monotonic = Stopwatch()..start();

Duration _now() => _monotonic.elapsed;

/// 一章的排版结果（设计 D3 到 D7）。
///
/// - 纯数据（每段的行、页）整章保留；绘制用的 painter 按需创建，只留当前页附近的（[retainAround]）。
/// - 切页从章首往后增量进行：[layoutThrough] 同步排到目标页再多一页，[layoutInBackground] 把剩下的分帧排完。
/// - 每个对象就是一代排版：参数变了就新建一个，旧的 [dispose] 以后，它还没执行的分帧任务不再改动任何结果。
class ChapterLayout extends ChangeNotifier {
  ChapterLayout(this.chapter, this.spec, {this.isVolume = false, Duration Function()? clock}) : _clock = clock ?? _now {
    _titleHeight = _measureTitle();
    _y = titleBlockHeight;
    if (chapter.paragraphs.isEmpty) _closePage();
  }

  final FormattedChapter chapter;
  final LayoutSpec spec;

  /// 卷只有一页，只有卷名（reader「分页排版」）。
  final bool isVolume;

  final Duration Function() _clock;

  late final double _titleHeight;

  /// 章节名占的高度，含下面空出的一个字高。
  double get titleBlockHeight => _titleHeight + spec.fontSize;
  late final List<ParagraphLines?> _paragraphs = List.filled(chapter.paragraphs.length, null);

  /// 已经切好的页。没排完时最后还有一页正在填，不在这里面。
  final List<ChapterPage> pages = [];

  bool _disposed = false;

  bool get complete => _next == chapter.paragraphs.length && _open == null;

  // ---------------------------------------------------------------- 文字样式

  TextStyle _body(Color color) => TextStyle(fontSize: spec.fontSize, color: color);

  StrutStyle get _strut => StrutStyle(
    fontSize: spec.fontSize,
    height: spec.lineHeight,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
  );

  TextStyle _titleStyle(Color color) =>
      TextStyle(fontSize: spec.fontSize * 1.3, height: spec.lineHeight, fontWeight: FontWeight.w600, color: color);

  TextPainter _painter(InlineSpan span, double width, {int? maxLines, TextAlign align = TextAlign.justify}) =>
      TextPainter(text: span, textAlign: align, textDirection: TextDirection.ltr, strutStyle: _strut, maxLines: maxLines)
        ..layout(minWidth: width, maxWidth: width);

  TextPainter _titlePainter(Color color) => TextPainter(
    text: TextSpan(text: chapter.title, style: _titleStyle(color)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: spec.size.width);

  double _measureTitle() {
    final painter = _titlePainter(const Color(0xFF000000));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  // ---------------------------------------------------------------- 段落

  /// 第 [index] 段的行（设计 D4）。第一次用到时同步排版，之后读缓存；量完就释放 painter（设计 D7）。
  ParagraphLines linesOf(int index) => _paragraphs[index] ??= _measure(chapter.paragraphs[index].text);

  ParagraphLines _measure(String text) {
    final style = _body(const Color(0xFF000000));
    final first = _painter(TextSpan(text: text, style: style), spec.size.width - spec.indent, maxLines: 1);
    final firstEnd = first.didExceedMaxLines ? first.getLineBoundary(const TextPosition(offset: 0)).end : text.length;
    final lines = <Line>[];
    _addLines(lines, first, 0, 0, isFirst: true);
    if (firstEnd < text.length) {
      final rest = _painter(TextSpan(text: text.substring(firstEnd), style: style), spec.size.width);
      _addLines(lines, rest, firstEnd, first.height, isFirst: false);
      rest.dispose();
    }
    final height = lines.last.top + lines.last.height;
    first.dispose();
    return (lines: lines, firstEnd: firstEnd, height: height);
  }

  /// 每行的行盒：行距平均分到字的上下（`leadingDistribution: even`），`baseline - ascent` 是字形的顶部，
  /// 比行盒顶部低半个行距。所以各行一起往上平移首行的这段距离，最后一行一直到 painter 底部：
  /// 行盒首尾相接、铺满整个 painter，切页累加的高度和实际绘制的位置一致。
  static void _addLines(List<Line> lines, TextPainter painter, int base, double top, {required bool isFirst}) {
    final metrics = painter.computeLineMetrics();
    final lead = metrics.first.baseline - metrics.first.ascent;
    final tops = [for (final metric in metrics) metric.baseline - metric.ascent - lead, painter.height];
    final length = painter.plainText.length;
    var offset = 0;
    for (var i = 0; i < metrics.length; i++) {
      // 首行被 maxLines 截断，plainText 是整段；其余行里最后一行一直到文字末尾
      final end = isFirst || i < metrics.length - 1 ? painter.getLineBoundary(TextPosition(offset: offset)).end : length;
      lines.add((start: base + offset, end: base + end, top: top + tops[i], height: tops[i + 1] - tops[i]));
      offset = end;
    }
  }

  /// 一页上的文字（章节名和各行），给读屏软件用。
  String pageText(int index) {
    final page = pages[index];
    return [
      if (page.hasTitle) chapter.title,
      for (final s in page.segments)
        chapter.paragraphs[s.paragraph].text.substring(linesOf(s.paragraph).lines[s.from].start, linesOf(s.paragraph).lines[s.to - 1].end),
    ].join('\n');
  }

  /// 第 [index] 段第 [line] 行首字在本章里的偏移。
  int offsetOf(int index, int line) => chapter.paragraphs[index].offset + linesOf(index).lines[line].start;

  // ---------------------------------------------------------------- 切页

  int _next = 0;

  @visibleForTesting
  int get debugPlacedParagraphs => _next;

  List<Segment>? _open = [];
  bool _openHasTitle = true;
  int _openStart = 0;
  int _openEnd = 0;
  double _y = 0;

  /// 把下一段放进页里（设计 D5）：逐行往下放，同一页上段与段之间加段距，放不下就换页；
  /// 一页还空着（没有正文也没有章节名）时第一行都放不下，就强制放下这一行。
  void _placeNext() {
    final index = _next++;
    final paragraph = linesOf(index);
    if (_open!.isNotEmpty) _y += spec.paragraphSpacing;
    var from = 0;
    var top = _y;
    for (final (i, line) in paragraph.lines.indexed) {
      final empty = _open!.isEmpty && !_openHasTitle && i == from;
      if (_y + line.height > spec.size.height && !empty) {
        if (i > from) {
          _open!.add((paragraph: index, from: from, to: i, top: top));
          _openEnd = chapter.paragraphs[index].offset + paragraph.lines[i - 1].end;
        }
        _closePage();
        _open = [];
        _openHasTitle = false;
        _openStart = offsetOf(index, i);
        (from, top) = (i, 0);
        _y = 0;
      }
      _y += line.height;
    }
    _open!.add((paragraph: index, from: from, to: paragraph.lines.length, top: top));
    _openEnd = chapter.paragraphs[index].offset + paragraph.lines.last.end;
    if (_next == chapter.paragraphs.length) _closePage();
  }

  void _closePage() {
    pages.add(ChapterPage(segments: _open!, hasTitle: _openHasTitle, start: _openStart, end: _openEnd));
    _open = null;
  }

  /// 包含偏移 [offset] 的页：已切好的页里，最后一个起始偏移不大于它的（二分查找）。
  int pageAt(int offset) {
    var (low, high) = (0, pages.length - 1);
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (pages[mid].start <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// 同步排到包含 [offset] 的那一页，再多排一页（设计 D6），让往后翻立刻就有内容。
  void layoutThrough(int offset) {
    final before = pages.length;
    while (!complete && (pages.isEmpty || pages.length < pageAt(offset) + 2)) {
      _placeNext();
    }
    if (pages.length != before) notifyListeners();
  }

  /// 排一批：直到用完 [budget] 或者排完。返回是否排完。
  bool layoutSlice([Duration budget = const Duration(milliseconds: 4)]) {
    final start = _clock();
    final before = pages.length;
    while (!complete && _clock() - start < budget) {
      _placeNext();
    }
    if (pages.length != before) notifyListeners();
    return complete;
  }

  /// 剩下的部分分帧排完（设计 D6）。每次只排一批，没排完就再排一次；[dispose] 以后的任务直接丢弃。
  void layoutInBackground([LayoutScheduler schedule = scheduleNextFrame]) {
    void task() {
      if (_disposed || layoutSlice()) return;
      schedule(task);
    }

    if (!complete) schedule(task);
  }

  // ---------------------------------------------------------------- painter（设计 D7、D8）

  final Map<(int, int, int), SegmentPainter> _painters = {};
  Color? _painterColor;

  @visibleForTesting
  int debugPaintersCreated = 0;

  @visibleForTesting
  int debugPaintersDisposed = 0;

  @visibleForTesting
  int get debugLivePainters => _painters.length;

  /// 画第 [segment] 用的 painter。整段都在这一页的段落用整段 painter；跨页的段落，每页一个页内 painter，
  /// 文字和整段相同，只是这一页以外的行用透明色：颜色不影响排版，行的位置和切页时量的一样，
  /// 又不用裁剪，相邻行伸出行盒的字形不会露进本页（设计 D8）。
  SegmentPainter painterFor(Segment segment, Color color) {
    _recolor(color);
    return _painters[(segment.paragraph, segment.from, segment.to)] ??= _create(segment.paragraph, segment.from, segment.to, color);
  }

  /// 章节名的 painter，也放在缓存里，键是 (-1, 0, 0)。
  SegmentPainter titlePainter(Color color) {
    _recolor(color);
    return _painters[(-1, 0, 0)] ??= _count(SegmentPainter._(first: _titlePainter(color), rest: null, indent: 0, top: 0, restTop: 0));
  }

  void _recolor(Color color) {
    if (_painterColor == color) return;
    _clearPainters((_) => true);
    _painterColor = color;
  }

  SegmentPainter _create(int index, int from, int to, Color color) {
    final text = chapter.paragraphs[index].text;
    final paragraph = linesOf(index);
    final lines = paragraph.lines;
    final visible = _body(color);
    final hidden = _body(const Color(0x00000000));
    final start = lines[from].start, end = lines[to - 1].end;

    /// [base, base + part.length) 这一部分文字的 span：[start, end) 用正文颜色，其余透明。
    InlineSpan span(String part, int base) {
      if (start <= base && end >= base + part.length) return TextSpan(text: part, style: visible);
      final a = (start - base).clamp(0, part.length), b = (end - base).clamp(0, part.length);
      return TextSpan(
        children: [
          if (a > 0) TextSpan(text: part.substring(0, a), style: hidden),
          if (b > a) TextSpan(text: part.substring(a, b), style: visible),
          if (b < part.length) TextSpan(text: part.substring(b), style: hidden),
        ],
      );
    }

    final firstText = text.substring(0, paragraph.firstEnd);
    final restText = text.substring(paragraph.firstEnd);
    // 首行不在这一页时不用排首行，只有首行在这一页时不用排后面的行
    final first = from == 0 ? _painter(span(text, 0), spec.size.width - spec.indent, maxLines: 1) : null;
    final rest = to > 1 && restText.isNotEmpty ? _painter(span(restText, firstText.length), spec.size.width) : null;
    assert(rest == null || _sameBreaks(rest, lines.sublist(1), firstText.length), '页内 painter 的断行和量出来的不一致');
    return _count(
      SegmentPainter._(first: first, rest: rest, indent: spec.indent, top: lines[from].top, restTop: lines.length > 1 ? lines[1].top : 0),
    );
  }

  bool _sameBreaks(TextPainter painter, List<Line> lines, int base) {
    final measured = <Line>[];
    _addLines(measured, painter, base, 0, isFirst: false);
    return measured.length == lines.length &&
        [for (var i = 0; i < lines.length; i++) measured[i].start == lines[i].start].every((same) => same);
  }

  SegmentPainter _count(SegmentPainter painter) {
    debugPaintersCreated++;
    return painter;
  }

  /// 只留页 [page] 前后各两页用到的 painter（含章节名），其余释放（设计 D7）。
  /// 这几页里出现的段落，整段 painter 也留着：滚动模式按段画，用的是整段 painter（设计 D12）。
  void retainAround(int page) {
    final keep = <(int, int, int)>{};
    for (var i = (page - 2).clamp(0, pages.length); i < (page + 3).clamp(0, pages.length); i++) {
      if (pages[i].hasTitle) keep.add((-1, 0, 0));
      for (final s in pages[i].segments) {
        keep
          ..add((s.paragraph, s.from, s.to))
          ..add((s.paragraph, 0, linesOf(s.paragraph).lines.length));
      }
    }
    _clearPainters((key) => !keep.contains(key));
  }

  void _clearPainters(bool Function((int, int, int) key) test) {
    _painters.removeWhere((key, painter) {
      if (!test(key)) return false;
      painter._dispose();
      debugPaintersDisposed++;
      return true;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clearPainters((_) => true);
    super.dispose();
  }
}

/// 画一个 Segment：首行 painter 向右平移一个缩进，其余行接在首行下面（设计 D8）。
/// 由 [ChapterLayout] 创建和释放，调用方不要自己 dispose。
final class SegmentPainter {
  SegmentPainter._({required this.first, required this.rest, required this.indent, required this.top, required this.restTop});

  final TextPainter? first;
  final TextPainter? rest;
  final double indent;

  /// Segment 第一行在段内的 top：画的时候整段往上移这么多，让这一行落在 [paint] 给的位置。
  final double top;

  /// 第二行在段内的 top，也就是其余行 painter 的位置。
  final double restTop;

  /// 把 Segment 的第一行画在 [offset]。
  void paint(Canvas canvas, Offset offset) {
    first?.paint(canvas, offset + Offset(indent, -top));
    rest?.paint(canvas, offset + Offset(0, restTop - top));
  }

  void _dispose() {
    first?.dispose();
    rest?.dispose();
  }
}
