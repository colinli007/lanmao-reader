import 'package:flutter/material.dart';

import 'two_pass.dart';

/// 1.5 的摆放方式：覆盖（渐变阴影）、覆盖（BoxShadow）、滑动；[baseline] 只平移一个纯色块，
/// 用来看出这台设备上 raster 耗时的底数（模拟器上 raster 会包含等待交换缓冲区的时间）。
enum TurnDemoMode { baseline, coverGradient, coverBoxShadow, slide }

/// 1.5 翻页帧耗时的演示：两页真实正文（多段裁剪绘制），用一个 AnimationController 往返播放翻页（D10）。
class TurnDemo extends StatefulWidget {
  const TurnDemo({super.key, required this.paragraphs, required this.mode});

  final List<String> paragraphs;
  final TurnDemoMode mode;

  @override
  State<TurnDemo> createState() => TurnDemoState();
}

class TurnDemoState extends State<TurnDemo> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  _Pages? _pages;

  /// 往返播放，直到 [stop]。
  void play() => controller.repeat(reverse: true);

  void stop() => controller.stop();

  @override
  void dispose() {
    controller.dispose();
    _pages?.dispose();
    super.dispose();
  }

  _Pages _layout(Size size) {
    if (_pages case final pages? when pages.size == size) return pages;
    _pages?.dispose();
    return _pages = _Pages(widget.paragraphs, size);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = EdgeInsets.fromLTRB(20, 28, 20, 28);
        final pages = _layout(margin.deflateSize(constraints.biggest));
        Widget page(int index) => RepaintBoundary(
          child: ColoredBox(
            color: const Color(0xFFF5F0E1),
            child: Padding(
              padding: margin,
              child: CustomPaint(size: Size.infinite, painter: _PagePainter(pages, index)),
            ),
          ),
        );
        final width = constraints.maxWidth;
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        double snap(double x) => (x * pixelRatio).roundToDouble() / pixelRatio;
        final current = page(0), next = page(1);
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            return Stack(
              children: switch (widget.mode) {
                TurnDemoMode.baseline => [
                  Transform.translate(
                    offset: Offset(snap(-t * width), 0),
                    child: const ColoredBox(color: Color(0xFFF5F0E1), child: SizedBox.expand()),
                  ),
                ],
                TurnDemoMode.slide => [
                  Transform.translate(offset: Offset(snap(-t * width), 0), child: current),
                  Transform.translate(offset: Offset(snap((1 - t) * width), 0), child: next),
                ],
                TurnDemoMode.coverGradient || TurnDemoMode.coverBoxShadow => [
                  next,
                  Transform.translate(
                    offset: Offset(snap(-t * width), 0),
                    child: widget.mode == TurnDemoMode.coverGradient
                        ? _GradientShadow(child: current)
                        : DecoratedBox(
                            decoration: const BoxDecoration(
                              boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 16)],
                            ),
                            child: current,
                          ),
                  ),
                ],
              },
            );
          },
        );
      },
    );
  }
}

/// 移动页右边缘外侧约 16 逻辑像素宽的线性渐变阴影（D10）。
class _GradientShadow extends StatelessWidget {
  const _GradientShadow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(child: child),
      const Positioned(
        top: 0,
        bottom: 0,
        right: -16,
        width: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Color(0x55000000), Color(0x00000000)]),
          ),
        ),
      ),
    ],
  );
}

/// 前两页的排版结果，painter 在演示期间一直留着。
class _Pages {
  _Pages(List<String> paragraphs, this.size) {
    segments = paginate(paragraphs, const TypesetStyle(), size, maxPages: 2, onLaidOut: laidOut.add);
  }

  final Size size;
  final List<TwoPassParagraph> laidOut = [];
  late final List<List<Segment>> segments;

  void dispose() {
    for (final paragraph in laidOut) {
      paragraph.dispose();
    }
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.pages, this.index);

  final _Pages pages;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    for (final segment in pages.segments[index]) {
      pages.laidOut[segment.paragraph].paintLines(canvas, Offset(0, segment.top), segment.from, segment.to);
    }
  }

  @override
  bool shouldRepaint(_PagePainter oldDelegate) => oldDelegate.pages != pages || oldDelegate.index != index;
}
