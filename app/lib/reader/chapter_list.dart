import 'package:flutter/material.dart';

import '../storage/database.dart';

/// 目录：卷显示为分组标题、不能点击，[current] 是当前章节（标出并滚到附近）。详情页的目录和阅读页的目录共用。
class ChapterList extends StatefulWidget {
  const ChapterList({super.key, required this.chapters, required this.onSelect, this.current});

  final List<TocChapter> chapters;
  final int? current;
  final ValueChanged<int> onSelect;

  @override
  State<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<ChapterList> {
  static const _itemExtent = 48.0;

  late final _controller = ScrollController(initialScrollOffset: ((widget.current ?? 0) - 3).clamp(0, 1 << 30) * _itemExtent);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: _controller,
      itemExtent: _itemExtent,
      itemCount: widget.chapters.length,
      itemBuilder: (context, index) {
        final chapter = widget.chapters[index];
        if (chapter.isVolume) {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(chapter.title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        }
        return ListTile(
          title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: index == widget.current,
          onTap: () => widget.onSelect(index),
        );
      },
    );
  }
}
