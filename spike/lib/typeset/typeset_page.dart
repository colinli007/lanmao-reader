import 'package:flutter/material.dart';

import 'measure.dart';
import 'two_pass.dart';

/// 1.1、1.2、1.6 的验证页。红线标出正文区域的左边缘、缩进位置和右边缘，截图后对照。
class TypesetCheckPage extends StatelessWidget {
  const TypesetCheckPage({super.key, this.boundaryKey});

  /// 截图用：包住整页内容的 RepaintBoundary。
  final GlobalKey? boundaryKey;

  static const margin = 20.0;

  @override
  Widget build(BuildContext context) {
    const style = TypesetStyle();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: Colors.white,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth - margin * 2;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: margin, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Caption('（a）正文带「　　」+ TextAlign.justify'),
                        _Guides(
                          style: style,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final text in sampleParagraphs)
                                Padding(
                                  padding: EdgeInsets.only(bottom: style.paragraphSpacing),
                                  child: Text(
                                    '　　$text',
                                    style: style.text,
                                    strutStyle: style.strut,
                                    textAlign: TextAlign.justify,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const _Caption('（b）D4 两次排版'),
                        _Guides(
                          style: style,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final text in sampleParagraphs)
                                Padding(
                                  padding: EdgeInsets.only(bottom: style.paragraphSpacing),
                                  child: _TwoPass(text: text, style: style, width: width),
                                ),
                            ],
                          ),
                        ),
                        const _Caption('（c）占位符缩进（WidgetSpan）'),
                        _Guides(
                          style: style,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final text in sampleParagraphs)
                                Padding(
                                  padding: EdgeInsets.only(bottom: style.paragraphSpacing),
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        WidgetSpan(child: SizedBox(width: style.indent, height: 1)),
                                        TextSpan(text: text),
                                      ],
                                    ),
                                    style: style.text,
                                    strutStyle: style.strut,
                                    textAlign: TextAlign.justify,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        for (final lineHeight in [1.0, 1.4, 1.8]) ...[
                          _Caption('（d）字形出框：行距 $lineHeight，只画中间几行'),
                          _ClippedPage(style: TypesetStyle(lineHeight: lineHeight), width: width),
                        ],
                        const _Caption('测量'),
                        for (final text in sampleParagraphs) ...[
                          Text('a  ${describe(measureFullWidthSpaces(text, style, width), width)}', style: _small),
                          Text('b  ${describe(measureTwoPass(text, style, width), width)}', style: _small),
                          Text('c  ${describe(measurePlaceholder(text, style, width), width)}', style: _small),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _small = TextStyle(fontSize: 11, color: Colors.black87);

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.blue)),
  );
}

/// 在内容上面画三条红线：x = 0、缩进、正文宽度。
class _Guides extends StatelessWidget {
  const _Guides({required this.style, required this.child});

  final TypesetStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _GuidePainter(style.indent), child: child);
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.indent);

  final double indent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x88FF0000)
      ..strokeWidth = 0.5;
    for (final x in [0.0, indent, size.width]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => oldDelegate.indent != indent;
}

class _TwoPass extends StatelessWidget {
  const _TwoPass({required this.text, required this.style, required this.width});

  final String text;
  final TypesetStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final paragraph = TwoPassParagraph(text, style, width);
    final height = paragraph.height;
    paragraph.dispose();
    return CustomPaint(size: Size(width, height), painter: _ParagraphPainter(text, style));
  }
}

class _ParagraphPainter extends CustomPainter {
  _ParagraphPainter(this.text, this.style);

  final String text;
  final TypesetStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = TwoPassParagraph(text, style, size.width);
    paragraph.paint(canvas, Offset.zero);
    paragraph.dispose();
  }

  @override
  bool shouldRepaint(_ParagraphPainter oldDelegate) => oldDelegate.text != text;
}

/// 1.6：把 [glyphOverflowText] 排成一段，只画第 2 行到倒数第 2 行（裁剪绘制），灰底标出「页」的范围。
class _ClippedPage extends StatelessWidget {
  const _ClippedPage({required this.style, required this.width});

  final TypesetStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final paragraph = TwoPassParagraph(glyphOverflowText, style, width);
    final lines = paragraph.lines;
    final height = lines[lines.length - 2].top + lines[lines.length - 2].height - lines[1].top;
    paragraph.dispose();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFEFEFEF),
      child: CustomPaint(size: Size(width, height), painter: _ClippedPainter(style)),
    );
  }
}

class _ClippedPainter extends CustomPainter {
  _ClippedPainter(this.style);

  final TypesetStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = TwoPassParagraph(glyphOverflowText, style, size.width);
    paragraph.paintLines(canvas, Offset.zero, 1, paragraph.lines.length - 1);
    paragraph.dispose();
  }

  @override
  bool shouldRepaint(_ClippedPainter oldDelegate) => oldDelegate.style.lineHeight != style.lineHeight;
}
