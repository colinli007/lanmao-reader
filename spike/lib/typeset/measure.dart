/// 1.1、1.2、1.6 的测量：缩进位置、每行右边缘、末行是否被拉伸、裁剪后页边露出的像素。
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'two_pass.dart';

/// 验证用的段落：一段单行，两段多行（其中一段中英混排）。
const sampleParagraphs = [
  '他点了点头。',
  '山风从谷底卷上来，吹得崖边的松枝簌簌作响。他站在最高的那块石头上，望着远处渐渐亮起来的天色，心里反复想着昨夜师父说过的那几句话，却怎么也想不明白。',
  '他打开 iPhone 15 Pro Max，在 GitHub 上搜索 flutter reader，第 3 个结果有 1,024 颗星，作者说 v2.0 会支持 EPUB 和 TXT 两种格式。',
];

/// 一段的测量结果。[firstX] 是第一个字的横坐标；[rightEdges] 是除末行外每行最后一个字的右边缘；
/// [lastAdvance] 是末行平均每个字的宽度（不拉伸时约等于字号，中英混排时偏小）。
typedef ParagraphMeasure = ({int lines, double firstX, List<double> rightEdges, double lastAdvance});

String describe(ParagraphMeasure m, double width) {
  final edges = m.rightEdges.map((e) => (e - width).toStringAsFixed(2)).join(', ');
  return '${m.lines} 行  首字 x=${m.firstX.toStringAsFixed(2)}  非末行右边缘−宽度=[$edges]  '
      '末行字宽=${m.lastAdvance.toStringAsFixed(2)}';
}

/// 每行的右边缘和平均字宽，以及第 [firstChar] 个字的左边缘；横坐标都加上 [dx]。
typedef _Lines = ({double firstX, List<double> rights, List<double> advances});

/// [boxes] 返回 [start, end) 的字形框，[ranges] 是每行的字符区间。TextPainter 和 ui.Paragraph 共用。
/// 行尾的空格在软换行时挂在行外，量右边缘时跳过，取最后一个非空白的字。
_Lines _lines(
  String text,
  List<TextBox> Function(int start, int end) boxes,
  List<(int, int)> ranges,
  int firstChar,
  double dx,
) {
  double left(int i) => boxes(i, i + 1).first.left;
  double right(int i) => boxes(i, i + 1).last.right;
  int lastVisible(int end) => text.substring(0, end).trimRight().length;
  return (
    firstX: dx + left(firstChar),
    rights: [for (final (_, end) in ranges) dx + right(lastVisible(end) - 1)],
    advances: [
      for (final (start, end) in ranges)
        if (start < firstChar ? firstChar : start case final from)
          (right(lastVisible(end) - 1) - left(from)) / (lastVisible(end) - from),
    ],
  );
}

/// 按行取字符区间：从每行的起点问 getLineBoundary。
List<(int, int)> _ranges(int lineCount, TextRange Function(int offset) boundary) {
  final ranges = <(int, int)>[];
  var offset = 0;
  for (var i = 0; i < lineCount; i++) {
    final end = boundary(offset).end;
    ranges.add((offset, end));
    offset = end;
  }
  return ranges;
}

_Lines _painterLines(TextPainter painter, int firstChar, double dx) => _lines(
  painter.plainText,
  (start, end) => painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end)),
  _ranges(painter.computeLineMetrics().length, (offset) => painter.getLineBoundary(TextPosition(offset: offset))),
  firstChar,
  dx,
);

ParagraphMeasure _combine(List<_Lines> parts) {
  final rights = [for (final part in parts) ...part.rights];
  return (
    lines: rights.length,
    firstX: parts.first.firstX,
    rightEdges: rights.sublist(0, rights.length - 1),
    lastAdvance: parts.last.advances.last,
  );
}

/// (a) 正文前面加「　　」，整段 `TextAlign.justify`。
ParagraphMeasure measureFullWidthSpaces(String text, TypesetStyle style, double width) {
  final painter = TextPainter(
    text: TextSpan(text: '　　$text', style: style.text),
    textAlign: TextAlign.justify,
    textDirection: TextDirection.ltr,
    strutStyle: style.strut,
  )..layout(minWidth: width, maxWidth: width);
  final result = _combine([_painterLines(painter, 2, 0)]);
  painter.dispose();
  return result;
}

/// (b) D4 的两次排版：首行画的时候向右平移一个缩进。
ParagraphMeasure measureTwoPass(String text, TypesetStyle style, double width) {
  final paragraph = TwoPassParagraph(text, style, width);
  final result = _combine([
    _painterLines(paragraph.first, 0, style.indent),
    if (paragraph.rest case final rest?) _painterLines(rest, 0, 0),
  ]);
  paragraph.dispose();
  return result;
}

/// (c) D4 的备选：段首一个两字宽的占位符（占位符占一个字符位置）。
ParagraphMeasure measurePlaceholder(String text, TypesetStyle style, double width) {
  final paragraph = placeholderParagraph(text, style, width);
  final result = _combine([
    _lines(
      '\uFFFC$text',
      (start, end) => paragraph.getBoxesForRange(start, end),
      _ranges(paragraph.computeLineMetrics().length, (offset) => paragraph.getLineBoundary(TextPosition(offset: offset))),
      1,
      0,
    ),
  ]);
  paragraph.dispose();
  return result;
}

/// 1.6 用的段落：每隔几个字放一个 emoji 或生僻字（会用回退字体）。
const glyphOverflowText =
    '他抬头😀看见𠀀天边𪚥升起一道🎉光芒，𡘙山谷里👨‍👩‍👧回荡着𠮷的笑声，龘龘靐齉🌕月色照在𩸽鱼身上，'
    'Ǻǻ Ṩṩ ÅÉ 的字母也在这里，🐉龙吟𠀋声声，𪜶们𠆢一起𤴓走向远方😭，最后𠂇又回到了起点🙏。';

/// 1.6 的测量结果：[neighbor] 是相邻行的字形伸进本页的像素数，[own] 是本页首末行被裁掉的像素数。
typedef OverflowMeasure = ({int neighbor, int own, int lines});

/// 用 [glyphOverflowText] 排出一段，取中间几行当作「一页」，按 D8 的方式裁剪绘制，量两种碎片：
/// - 相邻行伸进来的：本页的行用黑色、其余的行用透明色，和整段黑色比较。颜色不影响排版，两次的断行一样。
/// - 本行被裁掉的：本页的行用黑色、不裁剪，和裁剪后比较。
Future<OverflowMeasure> measureGlyphOverflow(TypesetStyle style, double width, double devicePixelRatio) async {
  TextPainter painter(InlineSpan span) => TextPainter(
    text: span,
    textAlign: TextAlign.justify,
    textDirection: TextDirection.ltr,
    strutStyle: style.strut,
  )..layout(minWidth: width, maxWidth: width);

  final probe = painter(TextSpan(text: glyphOverflowText, style: style.text));
  final metrics = probe.computeLineMetrics();
  final ranges = _ranges(metrics.length, (offset) => probe.getLineBoundary(TextPosition(offset: offset)));
  final from = 1, to = metrics.length - 1;
  final top = metrics[from].baseline - metrics[from].ascent;
  final bottom = metrics[to].baseline - metrics[to].ascent;
  final pageStart = ranges[from].$1, pageEnd = ranges[to - 1].$2;
  final height = probe.height;

  final transparent = style.text.copyWith(color: const Color(0x00000000));
  final onlyPage = painter(TextSpan(children: [
    TextSpan(text: glyphOverflowText.substring(0, pageStart), style: transparent),
    TextSpan(text: glyphOverflowText.substring(pageStart, pageEnd), style: style.text),
    TextSpan(text: glyphOverflowText.substring(pageEnd), style: transparent),
  ]));

  final sameBreaks = _ranges(metrics.length, (offset) => onlyPage.getLineBoundary(TextPosition(offset: offset)));
  assert('$sameBreaks' == '$ranges', '换颜色以后断行变了，比较没有意义');

  final clip = Rect.fromLTRB(0, top, width, bottom);
  Future<List<int>> render(TextPainter p, {required bool clipped}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    if (clipped) canvas.clipRect(clip);
    p.paint(canvas, Offset.zero);
    final image = await recorder.endRecording().toImage(
      (width * devicePixelRatio).ceil(),
      (height * devicePixelRatio).ceil(),
    );
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    return [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
  }

  int diff(List<int> a, List<int> b) {
    var count = 0;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 8) count++;
    }
    return count;
  }

  final whole = await render(probe, clipped: true);
  final pageClipped = await render(onlyPage, clipped: true);
  final pageUnclipped = await render(onlyPage, clipped: false);
  probe.dispose();
  onlyPage.dispose();
  return (neighbor: diff(whole, pageClipped), own: diff(pageUnclipped, pageClipped), lines: to - from);
}
