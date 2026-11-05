import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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

/// 画图片时要的位图（add-content-images 设计 D4）：解码好的直接给；还没有时开始解码并返回 null，解码完成后通知监听者。
/// [size] 是显示尺寸（逻辑像素）。
abstract interface class ImageBitmaps implements Listenable {
  ui.Image? bitmap(String src, Size size);
}

/// 图片的显示尺寸（reader「正文图片」，add-content-images 设计 D3）。正文宽 W、高 H 来自 [spec]。
Size imageDisplaySize(ContentImage image, LayoutSpec spec) {
  final (width, height) = (spec.size.width, spec.size.height);
  final lineHeight = spec.fontSize * spec.lineHeight;
  final natural = image.size;
  if (natural == null || natural.isEmpty) return Size(width, lineHeight * 3);
  var size = natural;
  if (_optionWidth(image.width, width) case final w?) size = Size(w, natural.height * w / natural.width);
  Size scaleTo(double w) => Size(w, size.height * w / size.width);
  Size capHeight(Size s) => s.height > height ? Size(s.width * height / s.height, height) : s;
  return switch (image.mode) {
    ImageMode.inline => Size(spec.fontSize, math.min(spec.fontSize * size.height / size.width, lineHeight)),
    ImageMode.normal => capHeight(size.width > width ? scaleTo(width) : size),
    ImageMode.full || ImageMode.single => capHeight(scaleTo(width)),
  };
}

/// 地址选项里的 `width`：`50%` 是正文宽的一半，数字是逻辑像素；认不出时为 null。
double? _optionWidth(String? option, double bodyWidth) {
  final text = option?.trim();
  if (text == null || text.isEmpty) return null;
  final value = double.tryParse(text.endsWith('%') ? text.substring(0, text.length - 1) : text);
  if (value == null || value <= 0) return null;
  return text.endsWith('%') ? bodyWidth * value / 100 : value;
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
  ChapterLayout(this.chapter, this.spec, {this.isVolume = false, this.images, Duration Function()? clock}) : _clock = clock ?? _now {
    images?.addListener(notifyListeners);
    _titleHeight = _measureTitle();
    _y = titleBlockHeight;
    if (chapter.paragraphs.isEmpty) _closePage();
  }

  final FormattedChapter chapter;
  final LayoutSpec spec;

  /// 卷只有一页，只有卷名（reader「分页排版」）。
  final bool isVolume;

  /// 正文图片的位图，没有时图片只画占位框；解码完成时这一章通知重画（add-content-images 设计 D4）。
  final ImageBitmaps? images;

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

  TextPainter _painter(_Span span, double width, {int? maxLines}) {
    final painter = TextPainter(text: span.span, textAlign: TextAlign.justify, textDirection: TextDirection.ltr, strutStyle: _strut, maxLines: maxLines);
    if (span.placeholders.isNotEmpty) {
      painter.setPlaceholderDimensions([
        for (final image in span.placeholders) PlaceholderDimensions(size: imageDisplaySize(image.image, spec), alignment: ui.PlaceholderAlignment.middle),
      ]);
    }
    return painter..layout(minWidth: width, maxWidth: width);
  }

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
  /// 单独成段的图片只有一行，字符区间 [0, 1)，高度是图片的显示高度（add-content-images 设计 D6）。
  ParagraphLines linesOf(int index) => _paragraphs[index] ??= _measure(index);

  ParagraphLines _measure(int index) {
    if (blockImageOf(chapter.paragraphs[index]) case final image?) {
      final height = imageDisplaySize(image, spec).height;
      return (lines: [(start: 0, end: 1, top: 0.0, height: height)], firstEnd: 1, height: height);
    }
    final text = chapter.paragraphs[index].text;
    final style = _body(const Color(0xFF000000));
    final first = _painter(_span(index, 0, style, style, (0, text.length)), spec.size.width - spec.indent, maxLines: 1);
    final firstEnd = first.didExceedMaxLines ? first.getLineBoundary(const TextPosition(offset: 0)).end : text.length;
    final lines = <Line>[];
    _addLines(lines, first, 0, 0, isFirst: true);
    if (firstEnd < text.length) {
      final rest = _painter(_span(index, firstEnd, style, style, (0, text.length)), spec.size.width);
      _addLines(lines, rest, firstEnd, first.height, isFirst: false);
      rest.dispose();
    }
    final height = lines.last.top + lines.last.height;
    first.dispose();
    return (lines: lines, firstEnd: firstEnd, height: height);
  }

  /// 第 [index] 段从 [from] 到段尾的 span：[visible] 区间里的字用 [shown]，其余用 [hidden]（颜色不影响排版，设计 D8）；
  /// 行内图换成占位（add-content-images 设计 D5），按出现的顺序记下对应的图片和它在段里的位置。
  _Span _span(int index, int from, TextStyle shown, TextStyle hidden, (int, int) visible) {
    final paragraph = chapter.paragraphs[index];
    final text = paragraph.text;
    final marks = [for (var i = 0; i < text.length; i++) if (text[i] == imageMark) i];
    if (marks.isEmpty && visible.$1 <= from && visible.$2 >= text.length) {
      return (span: TextSpan(text: text.substring(from), style: shown), placeholders: const []);
    }
    final cuts = {
      from,
      text.length,
      visible.$1.clamp(from, text.length),
      visible.$2.clamp(from, text.length),
      for (final mark in marks)
        if (mark >= from) ...[mark, mark + 1],
    }.toList()..sort();
    final children = <InlineSpan>[];
    final placeholders = <_Placeholder>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      final (a, b) = (cuts[i], cuts[i + 1]);
      final inView = a >= visible.$1 && b <= visible.$2;
      if (b == a + 1 && text[a] == imageMark) {
        children.add(const WidgetSpan(child: SizedBox.shrink(), alignment: ui.PlaceholderAlignment.middle));
        placeholders.add((image: paragraph.images[marks.indexOf(a)], position: a, visible: inView));
      } else {
        children.add(TextSpan(text: text.substring(a, b), style: inView ? shown : hidden));
      }
    }
    return (span: TextSpan(children: children), placeholders: placeholders);
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

  /// 一页上的文字（章节名和各行），给读屏软件用；图片读作「[图片]」。
  String pageText(int index) {
    final page = pages[index];
    return [
      if (page.hasTitle) chapter.title,
      for (final s in page.segments)
        chapter.paragraphs[s.paragraph].text
            .substring(linesOf(s.paragraph).lines[s.from].start, linesOf(s.paragraph).lines[s.to - 1].end)
            .replaceAll(imageMark, '[图片]'),
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

  /// 上一段是独占一页的图片：下一段从新的一页开始（add-content-images 设计 D6）。
  bool _breakBefore = false;

  /// 把下一段放进页里（设计 D5）：逐行往下放，同一页上段与段之间加段距，放不下就换页；
  /// 一页还空着（没有正文也没有章节名）时第一行都放不下，就强制放下这一行。
  /// `SINGLE` 图片前后都换页，在页里垂直居中（add-content-images 设计 D6）。
  void _placeNext() {
    final index = _next++;
    final paragraph = linesOf(index);
    final single = blockImageOf(chapter.paragraphs[index])?.mode == ImageMode.single;
    if ((single || _breakBefore) && (_open!.isNotEmpty || _openHasTitle)) _startPage(index, 0);
    _breakBefore = single;
    if (single) _y = (spec.size.height - paragraph.height) / 2;
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
        _startPage(index, i);
        (from, top) = (i, 0);
      }
      _y += line.height;
    }
    _open!.add((paragraph: index, from: from, to: paragraph.lines.length, top: top));
    _openEnd = chapter.paragraphs[index].offset + paragraph.lines.last.end;
    if (_next == chapter.paragraphs.length) _closePage();
  }

  /// 关掉正在填的页，从第 [index] 段第 [line] 行开始新的一页。
  void _startPage(int index, int line) {
    _closePage();
    _open = [];
    _openHasTitle = false;
    _openStart = offsetOf(index, line);
    _y = 0;
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
  /// 又不用裁剪，相邻行伸出行盒的字形不会露进本页（设计 D8）。单独成段的图片用图片 painter。
  SegmentPainter painterFor(Segment segment, Color color) {
    _recolor(color);
    return _painters[(segment.paragraph, segment.from, segment.to)] ??= _create(segment.paragraph, segment.from, segment.to, color);
  }

  /// 章节名的 painter，也放在缓存里，键是 (-1, 0, 0)。
  TextSegmentPainter titlePainter(Color color) {
    _recolor(color);
    return (_painters[(-1, 0, 0)] ??= _count(
          TextSegmentPainter._(first: _titlePainter(color), rest: null, indent: 0, top: 0, restTop: 0),
        ))
        as TextSegmentPainter;
  }

  /// 第 [page] 页上落在 [position]（相对正文区域左上角）的图片地址；没有、或者是加载失败的图片时为 null（reader「看大图」）。
  String? imageAt(int page, Offset position, Color color) {
    for (final segment in pages[page].segments) {
      final src = painterFor(segment, color).imageAt(position - Offset(0, segment.top));
      if (src != null) return src;
    }
    return null;
  }

  void _recolor(Color color) {
    if (_painterColor == color) return;
    _clearPainters((_) => true);
    _painterColor = color;
  }

  SegmentPainter _create(int index, int from, int to, Color color) {
    if (blockImageOf(chapter.paragraphs[index]) case final image?) {
      return _count(ImageSegmentPainter._(image, imageDisplaySize(image, spec), spec.size.width, color, images));
    }
    final text = chapter.paragraphs[index].text;
    final paragraph = linesOf(index);
    final lines = paragraph.lines;
    final visible = (lines[from].start, lines[to - 1].end);
    final shown = _body(color);
    final hidden = _body(const Color(0x00000000));
    // 首行不在这一页时不用排首行，只有首行在这一页时不用排后面的行
    final first = from == 0 ? _span(index, 0, shown, hidden, visible) : null;
    final rest = to > 1 && paragraph.firstEnd < text.length ? _span(index, paragraph.firstEnd, shown, hidden, visible) : null;
    final firstPainter = first == null ? null : _painter(first, spec.size.width - spec.indent, maxLines: 1);
    final restPainter = rest == null ? null : _painter(rest, spec.size.width);
    assert(restPainter == null || _sameBreaks(restPainter, lines.sublist(1), paragraph.firstEnd), '页内 painter 的断行和量出来的不一致');
    return _count(
      TextSegmentPainter._(
        first: firstPainter,
        rest: restPainter,
        indent: spec.indent,
        top: lines[from].top,
        restTop: lines.length > 1 ? lines[1].top : 0,
        // 首行 painter 被 maxLines 截成一行，只画首行里的图
        firstImages: [...?first?.placeholders.where((p) => p.position < paragraph.firstEnd)],
        restImages: rest?.placeholders ?? const [],
        images: images,
        color: color,
      ),
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
  /// 这几页上的图片顺便开始解码，翻过去时通常已经解码好了（add-content-images 设计 D4）。
  void retainAround(int page) {
    final keep = <(int, int, int)>{};
    for (var i = (page - 2).clamp(0, pages.length); i < (page + 3).clamp(0, pages.length); i++) {
      if (pages[i].hasTitle) keep.add((-1, 0, 0));
      for (final s in pages[i].segments) {
        keep
          ..add((s.paragraph, s.from, s.to))
          ..add((s.paragraph, 0, linesOf(s.paragraph).lines.length));
        for (final image in chapter.paragraphs[s.paragraph].images) {
          if (!image.failed) images?.bitmap(image.src, imageDisplaySize(image, spec));
        }
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
    images?.removeListener(notifyListeners);
    _clearPainters((_) => true);
    super.dispose();
  }
}

/// 一段文字的 span，以及其中行内图的占位：对应的图片、在段里的位置、是否在要画的行里。
typedef _Placeholder = ({ContentImage image, int position, bool visible});
typedef _Span = ({InlineSpan span, List<_Placeholder> placeholders});

/// 画一个 Segment。由 [ChapterLayout] 创建和释放，调用方不要自己 dispose。
sealed class SegmentPainter {
  /// 把 Segment 的第一行画在 [offset]。
  void paint(Canvas canvas, Offset offset);

  /// 落在 [position]（相对 Segment 第一行的左上角）的图片地址；没有、或者是加载失败的图片时为 null。
  String? imageAt(Offset position);

  void _dispose();
}

/// 画一张图片：解码好就画位图，没有时画浅色方框等它解码（add-content-images 设计 D4）。
void _paintImage(Canvas canvas, Rect rect, ContentImage image, ImageBitmaps? images, Color color) {
  final bitmap = images?.bitmap(image.src, rect.size);
  if (bitmap == null) {
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.08));
    return;
  }
  final source = Rect.fromLTWH(0, 0, bitmap.width.toDouble(), bitmap.height.toDouble());
  canvas.drawImageRect(bitmap, source, rect, Paint()..filterQuality = FilterQuality.medium);
}

/// 文字段落：首行 painter 向右平移一个缩进，其余行接在首行下面（设计 D8）；画完文字再在占位上画行内图（add-content-images 设计 D5）。
final class TextSegmentPainter extends SegmentPainter {
  TextSegmentPainter._({
    required this.first,
    required this.rest,
    required this.indent,
    required this.top,
    required this.restTop,
    List<_Placeholder> firstImages = const [],
    List<_Placeholder> restImages = const [],
    this.images,
    this.color = const Color(0xFF000000),
  }) : _firstImages = firstImages,
       _restImages = restImages;

  final TextPainter? first;
  final TextPainter? rest;
  final double indent;

  /// Segment 第一行在段内的 top：画的时候整段往上移这么多，让这一行落在 [paint] 给的位置。
  final double top;

  /// 第二行在段内的 top，也就是其余行 painter 的位置。
  final double restTop;

  final List<_Placeholder> _firstImages;
  final List<_Placeholder> _restImages;
  final ImageBitmaps? images;
  final Color color;

  Offset get _firstOrigin => Offset(indent, -top);
  Offset get _restOrigin => Offset(0, restTop - top);

  @override
  void paint(Canvas canvas, Offset offset) {
    first?.paint(canvas, offset + _firstOrigin);
    rest?.paint(canvas, offset + _restOrigin);
    for (final (placeholder, rect) in _placed()) {
      _paintImage(canvas, rect.shift(offset), placeholder.image, images, color);
    }
  }

  @override
  String? imageAt(Offset position) {
    for (final (placeholder, rect) in _placed()) {
      if (rect.contains(position)) return placeholder.image.src;
    }
    return null;
  }

  /// 要画的行内图和它们的位置（相对 Segment 第一行的左上角）。
  Iterable<(_Placeholder, Rect)> _placed() sync* {
    for (final (painter, placeholders, origin) in [(first, _firstImages, _firstOrigin), (rest, _restImages, _restOrigin)]) {
      final boxes = painter?.inlinePlaceholderBoxes;
      if (boxes == null) continue;
      for (var i = 0; i < placeholders.length && i < boxes.length; i++) {
        if (placeholders[i].visible) yield (placeholders[i], boxes[i].toRect().shift(origin));
      }
    }
  }

  @override
  void _dispose() {
    first?.dispose();
    rest?.dispose();
  }
}

/// 单独成段的图片：水平居中；加载失败时画方框，中间写「图片加载失败」（reader「正文图片」）。
final class ImageSegmentPainter extends SegmentPainter {
  ImageSegmentPainter._(this.image, Size size, double width, this.color, this.images)
    : rect = Rect.fromLTWH((width - size.width) / 2, 0, size.width, size.height),
      _label = image.failed
          ? (TextPainter(
              text: TextSpan(text: '图片加载失败', style: TextStyle(fontSize: 14, color: color.withValues(alpha: 0.6))),
              textDirection: TextDirection.ltr,
            )..layout())
          : null;

  final ContentImage image;
  final Color color;
  final ImageBitmaps? images;

  /// 图片在段里的位置。
  final Rect rect;
  final TextPainter? _label;

  @override
  void paint(Canvas canvas, Offset offset) {
    final box = rect.shift(offset);
    final label = _label;
    if (label == null) return _paintImage(canvas, box, image, images, color);
    canvas.drawRect(
      box.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.3),
    );
    label.paint(canvas, box.center - Offset(label.width / 2, label.height / 2));
  }

  @override
  String? imageAt(Offset position) => !image.failed && rect.contains(position) ? image.src : null;

  @override
  void _dispose() => _label?.dispose();
}
