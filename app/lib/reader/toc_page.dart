import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../storage/database.dart';
import '../ui/icons.dart';
import '../ui/tokens.dart';

/// 一本书已缓存正文的章节地址。
final cachedChapterUrlsProvider = StreamProvider.autoDispose.family<Set<String>, String>(
  (ref, bookUrl) => ref.watch(databaseProvider).watchCachedChapterUrls(bookUrl),
);

/// 目录页（book-detail「目录」，redesign-minimal-ui 设计 D4）：阅读页和详情页共用。卷显示为分组标题、不能点击；
/// [current] 是当前章节，标出来并在打开时显示在可见区域内。点一章时带着它的下标返回。
class TocPage extends ConsumerStatefulWidget {
  const TocPage({super.key, required this.bookUrl, required this.bookName, required this.chapters, this.current});

  final String bookUrl;
  final String bookName;
  final List<TocChapter> chapters;
  final int? current;

  @override
  ConsumerState<TocPage> createState() => _TocPageState();
}

class _TocPageState extends ConsumerState<TocPage> {
  /// 行高固定，打开时直接算出当前章的滚动位置，几千章也不用逐行测量。
  static const _chapterExtent = 52.0;
  static const _volumeExtent = 44.0;

  /// 当前章上面留几行。
  static const _rowsAbove = 3;

  /// 列表里每一行在目录里的下标。正序时就是目录的顺序；倒序时卷的先后和卷里章节的先后都反过来，卷标题仍在卷的最前面。
  late List<int> _rows = _order(reversed: false);
  bool _reversed = false;
  late final int _total = widget.chapters.where((c) => !c.isVolume).length;
  late final _controller = ScrollController(initialScrollOffset: _offsetOfCurrent());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<int> _order({required bool reversed}) {
    if (!reversed) return [for (var i = 0; i < widget.chapters.length; i++) i];
    // 按卷分组：第一组是第一个卷之前的章节（可能为空），之后每组以卷开头
    final groups = <List<int>>[[]];
    for (final (index, chapter) in widget.chapters.indexed) {
      if (chapter.isVolume) groups.add([]);
      groups.last.add(index);
    }
    return [
      for (final group in groups.reversed)
        if (group.isNotEmpty && widget.chapters[group.first].isVolume) ...[group.first, ...group.skip(1).toList().reversed] else ...group.reversed,
    ];
  }

  double _extentOf(int index) => widget.chapters[index].isVolume ? _volumeExtent : _chapterExtent;

  /// 当前章那一行往上留 [_rowsAbove] 行的滚动位置。
  double _offsetOfCurrent() {
    final at = _rows.indexOf(widget.current ?? -1);
    var offset = 0.0;
    for (var i = 0; i < at - _rowsAbove; i++) {
      offset += _extentOf(_rows[i]);
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final cached = ref.watch(cachedChapterUrlsProvider(widget.bookUrl)).valueOrNull ?? const {};
    final current = widget.current;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName),
        actions: [
          IconButton(
            tooltip: _reversed ? '正序' : '倒序',
            icon: const Icon(LucideIcons.arrowDownUp),
            onPressed: () => setState(() {
              _reversed = !_reversed;
              _rows = _order(reversed: _reversed);
              _controller.jumpTo(0);
            }),
          ),
        ],
      ),
      floatingActionButton: current == null
          ? null
          : IconButton(
              tooltip: '回到当前',
              style: IconButton.styleFrom(backgroundColor: colors.fill, fixedSize: const Size(48, 48)),
              icon: const Icon(LucideIcons.locateFixed),
              onPressed: () => _controller.animateTo(
                _offsetOfCurrent().clamp(0, _controller.position.maxScrollExtent),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.item),
            child: Text('共 $_total 章 · 已缓存 ${cached.length} 章', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              itemCount: _rows.length,
              itemExtentBuilder: (index, _) => index < _rows.length ? _extentOf(_rows[index]) : null,
              itemBuilder: (context, index) {
                final at = _rows[index];
                final chapter = widget.chapters[at];
                if (chapter.isVolume) {
                  return Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }
                return InkWell(
                  onTap: () => Navigator.pop(context, at),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: at == current ? TextStyle(color: colors.accent, fontWeight: FontWeight.w600) : null,
                        ),
                      ),
                      if (cached.contains(chapter.url))
                        Icon(LucideIcons.checkCircle2, size: 16, color: colors.textSecondary, semanticLabel: '已缓存'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
