import 'package:flutter/material.dart';

import '../../storage/database.dart';
import '../../ui/icons.dart';
import '../../ui/tokens.dart';
import '../paged/chapter_window.dart';

/// 进度面板（reader「章节切换」，redesign-minimal-ui 设计 D5）：章节名、上一章、下一章、按章节拖动的进度条。
/// 进度条的每一格是一个不是卷的章节；拖动时只显示手指所在的章节名，松手才跳过去，跳转都从章首开始。
class ProgressPanel extends StatefulWidget {
  const ProgressPanel({super.key, required this.window, required this.chapters});

  final ChapterWindow window;
  final List<TocChapter> chapters;

  @override
  State<ProgressPanel> createState() => _ProgressPanelState();
}

class _ProgressPanelState extends State<ProgressPanel> {
  /// 不是卷的章节在目录里的下标，进度条的第 i 格对应 `_readable[i]`。
  late final List<int> _readable = [
    for (final (index, chapter) in widget.chapters.indexed)
      if (!chapter.isVolume) index,
  ];

  /// 拖动中手指所在的那一格，没在拖动时为空。
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: widget.window,
      builder: (context, _) {
        final window = widget.window;
        final previous = window.neighbor(window.chapter, -1);
        final next = window.neighbor(window.chapter, 1);
        final position = _readable.indexOf(window.chapter);
        final shown = _dragging == null ? window.chapter : _readable[_dragging!];
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.item, AppSpacing.page, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.chapters[shown].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textSecondary)),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一章',
                    icon: const Icon(LucideIcons.chevronLeft),
                    onPressed: previous == null ? null : () => window.open(previous),
                  ),
                  Expanded(
                    child: _readable.length < 2 || position < 0
                        ? const SizedBox.shrink()
                        : Slider(
                            value: (_dragging ?? position).toDouble(),
                            max: _readable.length - 1.0,
                            divisions: _readable.length - 1,
                            onChanged: (value) => setState(() => _dragging = value.round()),
                            onChangeEnd: (value) {
                              setState(() => _dragging = null);
                              final target = _readable[value.round()];
                              if (target != window.chapter) window.open(target);
                            },
                          ),
                  ),
                  IconButton(
                    tooltip: '下一章',
                    icon: const Icon(LucideIcons.chevronRight),
                    onPressed: next == null ? null : () => window.open(next),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
