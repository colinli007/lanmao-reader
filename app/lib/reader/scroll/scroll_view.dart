import 'package:flutter/material.dart';

import '../chapter_format.dart';
import '../layout/chapter_layout.dart';
import '../layout/page_painter.dart';
import '../paged/chapter_window.dart';
import '../reader_settings.dart';

/// 滚动模式（设计 D12）：一次显示一章，按段懒加载；和分页模式共用 [ChapterWindow] 里的排版结果，
/// 所以缩进、两端对齐、避头尾完全一样。章首有「上一章」，章末有「下一章」。
class ScrollReaderView extends StatefulWidget {
  const ScrollReaderView({super.key, required this.window, required this.theme, required this.menu});

  final ChapterWindow window;
  final ReaderTheme theme;

  /// 阅读菜单是否显示：点中间一行打开；显示时点任何位置都只隐藏菜单（reader「点击区域翻页」）。
  final ValueNotifier<bool> menu;

  /// 章首「上一章」那一行的高度。章首、章末都是固定高度，这样每一项的高度都能直接算出来。
  static const buttonRow = 56.0;
  static const footerHeight = 120.0;

  @override
  State<ScrollReaderView> createState() => _ScrollReaderViewState();
}

class _ScrollReaderViewState extends State<ScrollReaderView> {
  final _scroll = ScrollController();

  /// 已经定位过的排版结果：换章、改字号、刚切到滚动模式时，排版结果变了，要按读到的位置重新定位。
  ChapterLayout? _positioned;

  ChapterWindow get _window => widget.window;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 位置（设计 D12、D13）

  double _headerHeight(ChapterLayout layout) => ScrollReaderView.buttonRow + layout.titleBlockHeight;

  double _extent(ChapterLayout layout, int index) {
    if (index == 0) return _headerHeight(layout);
    if (index == layout.chapter.paragraphs.length + 1) return ScrollReaderView.footerHeight;
    return layout.linesOf(index - 1).height + layout.spec.paragraphSpacing;
  }

  /// 包含偏移 [offset] 的那一行顶部的滚动位置。
  double _scrollOffsetOf(ChapterLayout layout, int offset) {
    final paragraphs = layout.chapter.paragraphs;
    if (paragraphs.isEmpty || offset == 0) return 0;
    final index = paragraphAt(paragraphs, offset);
    var y = _headerHeight(layout);
    for (var i = 0; i < index; i++) {
      y += _extent(layout, i + 1);
    }
    final lines = layout.linesOf(index).lines;
    final within = offset - paragraphs[index].offset;
    final line = lines.lastWhere((line) => line.start <= within, orElse: () => lines.first);
    return y + line.top;
  }

  /// 滚动位置 [y] 处那一行的首字偏移：顶部还在章首时是 0。
  int _offsetAt(ChapterLayout layout, double y) {
    var top = _headerHeight(layout);
    if (y < top) return 0;
    for (final (i, paragraph) in layout.chapter.paragraphs.indexed) {
      final extent = _extent(layout, i + 1);
      if (y < top + extent) {
        final lines = layout.linesOf(i).lines;
        // 视口顶部落在某一行的中间时，取下一行：要的是屏幕上能看到的第一行
        final line = lines.firstWhere((line) => top + line.top >= y - 1, orElse: () => lines.last);
        return paragraph.offset + line.start;
      }
      top += extent;
    }
    final last = layout.chapter.paragraphs.lastOrNull;
    return last == null ? 0 : last.offset + layout.linesOf(layout.chapter.paragraphs.length - 1).lines.last.start;
  }

  /// 排版结果变了时，下一帧按读到的位置跳过去。
  void _positionAfterLayout(ChapterLayout layout) {
    if (identical(_positioned, layout)) return;
    _positioned = layout;
    final offset = _window.offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !identical(_positioned, layout)) return;
      _scroll.jumpTo(_scrollOffsetOf(layout, offset).clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  bool _onScroll(ScrollNotification notification) {
    final layout = _window.layoutOf(_window.chapter);
    if (notification is ScrollEndNotification && layout != null && identical(layout, _positioned)) {
      _window.anchorAt(_offsetAt(layout, _scroll.offset));
    }
    return false;
  }

  // ---------------------------------------------------------------- 点击区域

  void _onTapUp(TapUpDetails details) {
    if (widget.menu.value) {
      widget.menu.value = false;
      return;
    }
    final height = context.size!.height;
    final y = details.localPosition.dy;
    if (y > height / 3 && y < height * 2 / 3) {
      widget.menu.value = true;
      return;
    }
    if (!_scroll.hasClients) return;
    // 翻一屏减一行，留一行作为上下文
    final spec = _window.spec;
    final step = _scroll.position.viewportDimension - spec.fontSize * spec.lineHeight;
    final target = (_scroll.offset + (y < height / 3 ? -step : step)).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _window,
          builder: (context, _) => switch (_window.slotOf(_window.chapter)) {
            SlotReady(:final layout) => _chapter(layout),
            SlotFailed(:final message) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(message, style: TextStyle(color: widget.theme.foreground)),
                  ),
                  FilledButton(onPressed: () => _window.retry(_window.chapter), child: const Text('重试')),
                ],
              ),
            ),
            _ => Center(child: CircularProgressIndicator(color: widget.theme.foreground)),
          },
        ),
      ),
    );
  }

  Widget _chapter(ChapterLayout layout) {
    _positionAfterLayout(layout);
    final paragraphs = layout.chapter.paragraphs;
    final previous = _window.neighbor(_window.chapter, -1);
    final next = _window.neighbor(_window.chapter, 1);
    final color = widget.theme.foreground;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: PageGeometry.margin),
        itemCount: paragraphs.length + 2,
        itemExtentBuilder: (index, _) => index < paragraphs.length + 2 ? _extent(layout, index) : null,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: ScrollReaderView.buttonRow,
                  child: previous == null
                      ? null
                      : Center(
                          child: TextButton(onPressed: () => _window.open(previous), child: const Text('上一章')),
                        ),
                ),
                Semantics(
                  label: layout.chapter.title,
                  child: CustomPaint(size: Size.fromHeight(layout.titleBlockHeight), painter: _TitlePainter(layout, color)),
                ),
              ],
            );
          }
          if (index == paragraphs.length + 1) {
            return Center(
              child: next == null
                  ? Text('已是最后一章', style: TextStyle(color: color))
                  : FilledButton(onPressed: () => _window.open(next), child: const Text('下一章')),
            );
          }
          final paragraph = index - 1;
          return Semantics(
            label: paragraphs[paragraph].text,
            child: CustomPaint(painter: _ParagraphPainter(layout, paragraph, color)),
          );
        },
      ),
    );
  }
}

class _TitlePainter extends CustomPainter {
  _TitlePainter(this.layout, this.color);

  final ChapterLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => layout.titlePainter(color).paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_TitlePainter oldDelegate) => oldDelegate.layout != layout || oldDelegate.color != color;
}

/// 画整段（不裁剪），和分页模式用同一个 painter 缓存。
class _ParagraphPainter extends CustomPainter {
  _ParagraphPainter(this.layout, this.paragraph, this.color);

  final ChapterLayout layout;
  final int paragraph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = layout.linesOf(paragraph).lines.length;
    layout.painterFor((paragraph: paragraph, from: 0, to: lines, top: 0), color).paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_ParagraphPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.paragraph != paragraph || oldDelegate.color != color;
}
