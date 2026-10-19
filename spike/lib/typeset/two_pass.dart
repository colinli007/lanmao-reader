/// 分页排版验证用的排版原型：D4 的两次排版、行信息和按行切页。正式实现在 app 的 reader/layout 里。
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 段内的一行：字符区间 [start, end)，以及相对段落顶部的 top 和高度。
typedef Line = ({int start, int end, double top, double height});

/// 正文的排版参数。缩进是两个字宽。
class TypesetStyle {
  const TypesetStyle({this.fontSize = 18, this.lineHeight = 1.8, this.color = const Color(0xFF222222)});

  final double fontSize;
  final double lineHeight;
  final Color color;

  double get indent => fontSize * 2;
  double get paragraphSpacing => fontSize * 0.6;

  TextStyle get text => TextStyle(fontSize: fontSize, color: color);

  StrutStyle get strut => StrutStyle(
    fontSize: fontSize,
    height: lineHeight,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// D4：首行按「宽度 − 缩进」排一行（`maxLines: 1`），剩下的文字按整个宽度排。
class TwoPassParagraph {
  TwoPassParagraph(this.text, this.style, this.width) {
    first = _painter(text, maxLines: 1)..layout(minWidth: width - style.indent, maxWidth: width - style.indent);
    firstEnd = first.didExceedMaxLines ? first.getLineBoundary(const TextPosition(offset: 0)).end : text.length;
    _addLines(first, 0, 0);
    if (firstEnd < text.length) {
      rest = _painter(text.substring(firstEnd))..layout(minWidth: width, maxWidth: width);
      _addLines(rest!, firstEnd, first.height);
    }
  }

  final String text;
  final TypesetStyle style;
  final double width;
  late final TextPainter first;
  TextPainter? rest;
  late final int firstEnd;
  final List<Line> lines = [];

  double get height => first.height + (rest?.height ?? 0);

  TextPainter _painter(String text, {int? maxLines}) => TextPainter(
    text: TextSpan(text: text, style: style.text),
    textAlign: TextAlign.justify,
    textDirection: TextDirection.ltr,
    strutStyle: style.strut,
    maxLines: maxLines,
  );

  /// 每行的 top 取 `baseline - ascent`；高度取到下一行 top 的距离，最后一行取到 painter 底部，
  /// 这样各行高度加起来正好是 painter 的高度，切页累加的高度和实际绘制位置一致。
  void _addLines(TextPainter painter, int base, double top) {
    final metrics = painter.computeLineMetrics();
    final tops = [for (final metric in metrics) metric.baseline - metric.ascent, painter.height];
    var offset = 0;
    for (var i = 0; i < metrics.length; i++) {
      final end = painter == first || i < metrics.length - 1
          ? painter.getLineBoundary(TextPosition(offset: offset)).end
          : painter.plainText.length;
      lines.add((start: base + offset, end: base + end, top: top + tops[i], height: tops[i + 1] - tops[i]));
      offset = end;
    }
  }

  /// 画整段，左上角在 [offset]。
  void paint(Canvas canvas, Offset offset) {
    first.paint(canvas, offset + Offset(style.indent, 0));
    rest?.paint(canvas, offset + Offset(0, first.height));
  }

  /// 只画第 [from] 到 [to]（不含）行：裁剪到这几行，再把整段平移上来画（D8）。
  void paintLines(Canvas canvas, Offset offset, int from, int to) {
    final top = lines[from].top;
    final bottom = lines[to - 1].top + lines[to - 1].height;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(offset.dx, offset.dy, width, bottom - top));
    paint(canvas, offset - Offset(0, top));
    canvas.restore();
  }

  void dispose() {
    first.dispose();
    rest?.dispose();
  }
}

/// 页里的一段：第 [paragraph] 段的第 [from] 到 [to]（不含）行，画在页内 [top] 处。
typedef Segment = ({int paragraph, int from, int to, double top});

/// 按行切页（D5）：逐行往下放，同一页上段与段之间加段距，放不下就换页；空页上第一行都放不下时强制放下。
/// 排满 [maxPages] 页就停（用来量「排到第一页可以显示」的耗时）。返回每页的 Segment。
List<List<Segment>> paginate(
  List<String> paragraphs,
  TypesetStyle style,
  Size size, {
  int? maxPages,
  void Function(TwoPassParagraph paragraph)? onLaidOut,
}) {
  final pages = <List<Segment>>[[]];
  var y = 0.0;
  for (final (index, text) in paragraphs.indexed) {
    final paragraph = TwoPassParagraph(text, style, size.width);
    if (pages.last.isNotEmpty) y += style.paragraphSpacing;
    var from = 0;
    var top = y;
    for (final (i, line) in paragraph.lines.indexed) {
      if (y + line.height > size.height && !(pages.last.isEmpty && i == from)) {
        if (i > from) pages.last.add((paragraph: index, from: from, to: i, top: top));
        if (pages.length == maxPages) {
          onLaidOut?.call(paragraph);
          return pages;
        }
        pages.add([]);
        (from, top, y) = (i, 0, 0);
      }
      y += line.height;
    }
    pages.last.add((paragraph: index, from: from, to: paragraph.lines.length, top: top));
    onLaidOut?.call(paragraph);
  }
  return pages;
}

/// D4 的备选：段首放一个两字宽的占位符，整段一次排完。
ui.Paragraph placeholderParagraph(String text, TypesetStyle style, double width) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: TextAlign.justify,
      textDirection: TextDirection.ltr,
      fontSize: style.fontSize,
      strutStyle: ui.StrutStyle(
        fontSize: style.fontSize,
        height: style.lineHeight,
        forceStrutHeight: true,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    ),
  )
    ..pushStyle(style.text.getTextStyle())
    ..addPlaceholder(style.indent, style.fontSize, ui.PlaceholderAlignment.middle)
    ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: width));
}
