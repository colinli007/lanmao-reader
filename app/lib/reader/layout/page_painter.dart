import 'package:flutter/rendering.dart';

import '../reader_settings.dart';
import 'chapter_layout.dart';

/// 页面的几何（设计 D15）：页眉、页脚各高 28，字号 12，颜色是前景色的 60%；左右边距来自阅读设置（complete-reader-settings 设计 D2）。
abstract final class PageGeometry {
  static const header = 28.0;
  static const footer = 28.0;
  static const fontSize = 12.0;

  /// 正文区域离页面四边的距离：安全区加上左右边距 [margin] 和页眉页脚。
  static EdgeInsets bodyInsets(EdgeInsets safeArea, double margin) =>
      EdgeInsets.fromLTRB(safeArea.left + margin, safeArea.top + header, safeArea.right + margin, safeArea.bottom + footer);
}

/// 页脚的文字：「页码/本章总页数」，本章还没排完时只有页码（reader「页眉页脚」）。
String pageFooter(ChapterLayout layout, int index) => layout.complete ? '${index + 1}/${layout.pages.length}' : '${index + 1}';

/// 把一页画到画布上（设计 D8）：背景、页眉（章节名）、章节名（只有第一页）、正文、页脚（页码）。
///
/// 正文按 Segment 把 painter 平移到对应的位置画上去，不裁剪；跨页的段落用页内 painter（见 [ChapterLayout.painterFor]）。
/// 监听 [layout]：本章排完时页脚补上总页数。
class PagePainter extends CustomPainter {
  PagePainter({required this.layout, required this.index, required this.theme, required this.insets}) : super(repaint: layout);

  final ChapterLayout layout;
  final int index;
  final ReaderTheme theme;

  /// 正文区域离页面四边的距离，见 [PageGeometry.bodyInsets]。
  final EdgeInsets insets;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    final page = layout.pages[index];
    final color = theme.foreground;
    final width = size.width - insets.horizontal;
    final origin = Offset(insets.left, insets.top);

    final faint = TextStyle(fontSize: PageGeometry.fontSize, color: color.withValues(alpha: 0.6));
    _paintLine(
      canvas,
      layout.chapter.title,
      faint,
      Rect.fromLTWH(insets.left, insets.top - PageGeometry.header, width, PageGeometry.header),
    );
    _paintLine(
      canvas,
      pageFooter(layout, index),
      faint,
      Rect.fromLTWH(insets.left, size.height - insets.bottom, width, PageGeometry.footer),
      align: TextAlign.right,
    );

    if (page.hasTitle) {
      final title = layout.titlePainter(color);
      // 卷只有卷名，放在正文区域中间
      final at = layout.isVolume
          ? origin + Offset((width - title.first!.width) / 2, (size.height - insets.vertical - title.first!.height) / 2)
          : origin;
      title.paint(canvas, at);
    }
    for (final segment in page.segments) {
      layout.painterFor(segment, color).paint(canvas, origin + Offset(0, segment.top));
    }
  }

  /// 单行文字，超长加省略号，在 [box] 里垂直居中。
  static void _paintLine(Canvas canvas, String text, TextStyle style, Rect box, {TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: box.width, maxWidth: box.width);
    painter.paint(canvas, Offset(box.left, box.top + (box.height - painter.height) / 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(PagePainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.index != index || oldDelegate.theme != theme || oldDelegate.insets != insets;
}
