import 'package:flutter/material.dart';

import '../image_viewer_page.dart';
import '../layout/page_painter.dart';
import '../reader_settings.dart';
import 'chapter_window.dart';
import 'page_turn.dart';

/// 分页视图（设计 D10、D11、D15）：覆盖、滑动、无动画三种翻页方式，点击区域，章节之间连续翻页。
///
/// 页面来自 [window]；视图只决定翻不翻、怎么动，翻完再 [ChapterWindow.moveTo]。
class PagedView extends StatefulWidget {
  const PagedView({super.key, required this.window, required this.mode, required this.theme, required this.insets, required this.menu});

  final ChapterWindow window;
  final PageMode mode;
  final ReaderTheme theme;

  /// 正文区域离页面四边的距离（含安全区），见 [PageGeometry.bodyInsets]。
  final EdgeInsets insets;

  /// 阅读菜单是否显示：点中间一列打开；显示时点任何位置都只隐藏菜单（reader「点击区域翻页」）。
  final ValueNotifier<bool> menu;

  /// 点击翻页的动画时长和曲线（设计 D10）。
  static const turnDuration = Duration(milliseconds: 250);
  static const turnCurve = Curves.easeOut;

  @override
  State<PagedView> createState() => _PagedViewState();
}

/// 正在进行的一次翻页：要翻到的页、方向，以及松手或点击后是往完成走还是往回走。
typedef _Turn = ({WindowPage target, bool forward});

class _PagedViewState extends State<PagedView> with SingleTickerProviderStateMixin {
  /// 翻页进度 t（设计 D10）：0 是当前页在原位，1 是翻页完成。整个视图只用这一个 controller。
  late final AnimationController _controller = AnimationController(vsync: this);

  _Turn? _turn;
  bool _completing = false;

  /// 这次拖动已经判定过方向（开始拖动时确定）；为假时这次拖动不跟手（已到头或者在加载中的页）。
  bool? _dragFollows;
  double _dragDistance = 0;

  ChapterWindow get _window => widget.window;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 翻页

  /// 开始往 [forward] 方向翻；返回这次能不能翻。已到头时提示。
  bool _begin(bool forward) {
    switch (forward ? _window.pageAfter() : _window.pageBefore()) {
      case TurnTo(:final page):
        setState(() => _turn = (target: page, forward: forward));
        return true;
      case TurnAtEdge(:final first):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(first ? '已是第一章' : '已是最后一章'), duration: const Duration(seconds: 1)));
        return false;
      case TurnBlocked():
        return false;
    }
  }

  /// 动画走到终点：完成就翻到目标页，否则留在原页。
  void _finish() {
    final turn = _turn;
    if (turn == null) return;
    _controller.stop();
    setState(() {
      _turn = null;
      _controller.value = 0;
    });
    if (_completing) _window.moveTo(turn.target);
  }

  /// 从当前的 t 播放到终点：[complete] 为真走到 1，否则回到 0；时长按剩下的距离缩短（设计 D10）。
  void _animate({required bool complete}) {
    _completing = complete;
    if (widget.mode == PageMode.none) return _finish();
    final remaining = complete ? 1 - _controller.value : _controller.value;
    _controller
        .animateTo(complete ? 1 : 0, duration: PagedView.turnDuration * remaining, curve: PagedView.turnCurve)
        .then((_) => _finish());
  }

  /// 点击翻页。动画进行中又点时，先把当前这次直接提交，再开始下一次，不丢掉点击（reader「翻页方式」）。
  void _tapTurn(bool forward) {
    if (_turn != null) _finish();
    if (_begin(forward)) _animate(complete: true);
  }

  // ---------------------------------------------------------------- 手势（设计 D11）

  void _onTapUp(TapUpDetails details) {
    if (widget.menu.value) {
      widget.menu.value = false;
      return;
    }
    final width = context.size!.width;
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _tapTurn(false);
    } else if (x > width * 2 / 3) {
      _tapTurn(true);
    } else {
      widget.menu.value = true;
    }
  }

  /// 长按页面上的图片看大图（reader「看大图」）；菜单显示时、不在图片上时没有反应。
  void _onLongPressStart(LongPressStartDetails details) {
    final images = _window.images;
    if (widget.menu.value || _turn != null || images == null) return;
    if (_window.current case TextPage(:final chapter, page: final index)) {
      final position = details.localPosition - widget.insets.topLeft;
      final src = _window.layoutOf(chapter)!.imageAt(index, position, widget.theme.foreground);
      if (src != null) ImageViewerPage.open(context, src, images);
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_turn != null) _finish();
    _dragFollows = null;
    _dragDistance = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragDistance += details.primaryDelta ?? 0;
    // 往前翻还是往后翻，在第一次有位移时确定
    if (_dragFollows == null && _dragDistance != 0) _dragFollows = _begin(_dragDistance < 0);
    final turn = _turn;
    if (_dragFollows != true || turn == null) return;
    final t = ((turn.forward ? -_dragDistance : _dragDistance) / context.size!.width).clamp(0.0, 1.0);
    _controller.value = t;
  }

  void _onDragEnd(DragEndDetails details) {
    final turn = _turn;
    final follows = _dragFollows == true;
    _dragFollows = null;
    if (!follows || turn == null) return;
    _animate(
      complete: shouldComplete(velocity: details.primaryVelocity ?? 0, t: _controller.value, forward: turn.forward),
    );
  }

  void _onDragCancel() {
    if (_dragFollows == true && _turn != null) _animate(complete: false);
    _dragFollows = null;
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onLongPressStart: _onLongPressStart,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: ListenableBuilder(
        listenable: Listenable.merge([_window, _controller]),
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) => _pages(constraints.maxWidth)),
      ),
    );
  }

  Widget _pages(double width) {
    final turn = _turn;
    final current = _window.current;
    // 无动画模式拖动时页面不动（设计 D11）
    if (turn == null || widget.mode == PageMode.none) return Stack(fit: StackFit.expand, children: [_page(current, 0)]);
    final place = placePages(widget.mode, forward: turn.forward, t: _controller.value, width: width);
    final below = place.otherOnTop ? _page(current, place.current) : _page(turn.target, place.other);
    final above = place.otherOnTop ? _page(turn.target, place.other) : _page(current, place.current);
    final aboveX = place.otherOnTop ? place.other : place.current;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        below,
        above,
        // 覆盖：移动页的右边缘外侧一条渐变阴影（设计 D10）
        if (widget.mode == PageMode.cover)
          Positioned(top: 0, bottom: 0, left: _snap(aboveX + width), width: 16, child: const _EdgeShadow()),
      ],
    );
  }

  /// 位移取整到物理像素，避免文字发虚（设计 D8）。
  double _snap(double x) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return (x * ratio).roundToDouble() / ratio;
  }

  /// 一页：用页本身做 key，翻页过程中同一页的 RepaintBoundary 一直复用，动画只改外层的位移。
  Widget _page(WindowPage page, double x) => Transform.translate(
    key: ValueKey(page),
    offset: Offset(_snap(x), 0),
    child: RepaintBoundary(
      child: switch (page) {
        TextPage(:final chapter, page: final index) => Semantics(
          label: _window.layoutOf(chapter)!.pageText(index),
          child: CustomPaint(
            painter: PagePainter(layout: _window.layoutOf(chapter)!, index: index, theme: widget.theme, insets: widget.insets),
          ),
        ),
        PendingPage(:final chapter) => _PendingView(window: _window, chapter: chapter, theme: widget.theme),
      },
    ),
  );
}

class _EdgeShadow extends StatelessWidget {
  const _EdgeShadow();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x40000000), Color(0x00000000)])),
    ),
  );
}

/// 加载中的页和加载失败的页（reader「章节之间连续翻页」）。
class _PendingView extends StatelessWidget {
  const _PendingView({required this.window, required this.chapter, required this.theme});

  final ChapterWindow window;
  final int chapter;
  final ReaderTheme theme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.background,
      child: Center(
        child: switch (window.slotOf(chapter)) {
          SlotFailed(:final message) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(message, style: TextStyle(color: theme.foreground)),
              ),
              FilledButton(onPressed: () => window.retry(chapter), child: const Text('重试')),
            ],
          ),
          _ => CircularProgressIndicator(color: theme.foreground),
        },
      ),
    );
  }
}
