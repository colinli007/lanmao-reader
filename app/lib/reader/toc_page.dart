import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../storage/database.dart';
import '../ui/cinema.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart';

/// 目录（设计稿「阅读器 / 目录 · 影院」）：阅读页和详情页共用。卷显示为分组标题、不能点击，
/// [current] 是当前章节（标出「读到这里」并滚到附近）。点一章时带着它的序号返回。
class TocPage extends ConsumerStatefulWidget {
  const TocPage({super.key, required this.book, required this.chapters, this.current});

  final ShelfBook book;
  final List<TocChapter> chapters;
  final int? current;

  @override
  ConsumerState<TocPage> createState() => _TocPageState();
}

/// 列表里的一行：卷标题或章节。[ordinal] 是章节在全书里的序号（从 1 开始，不算卷）；
/// 卷的 [ordinal] 是卷里第一章的序号，[last] 是最后一章的序号，卷里没有章节时两者都为空。
typedef _Row = ({int index, int? ordinal, int? last});

class _TocPageState extends ConsumerState<TocPage> {
  static const _chapterExtent = 50.0;
  static const _currentExtent = 56.0;
  static const _volumeExtent = 64.0;

  /// 正序时就是目录的顺序；倒序时卷的先后和卷里章节的先后都反过来，卷标题仍在卷的最前面。
  late List<_Row> _rows;
  bool _reversed = false;
  late final int _total;

  /// 当前章在全书里的序号，没有当前章时是 0。
  late final int _currentOrdinal;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _rows = _build(reversed: false);
    _total = widget.chapters.where((c) => !c.isVolume).length;
    final current = widget.current;
    _currentOrdinal = current == null ? 0 : widget.chapters.take(current + 1).where((c) => !c.isVolume).length;
    _controller = ScrollController(initialScrollOffset: _offsetOfCurrent(rowsAbove: 3));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Row> _build({required bool reversed}) {
    final groups = <List<_Row>>[[]];
    var ordinal = 0;
    for (final (index, chapter) in widget.chapters.indexed) {
      if (chapter.isVolume) {
        groups.add([(index: index, ordinal: null, last: null)]);
      } else {
        groups.last.add((index: index, ordinal: ++ordinal, last: null));
      }
    }
    // 卷的章节范围
    for (final group in groups) {
      if (group.isNotEmpty && widget.chapters[group.first.index].isVolume && group.length > 1) {
        group[0] = (index: group.first.index, ordinal: group[1].ordinal, last: group.last.ordinal);
      }
    }
    if (!reversed) return [for (final group in groups) ...group];
    return [
      for (final group in groups.reversed)
        if (group.isNotEmpty && widget.chapters[group.first.index].isVolume) ...[
          group.first,
          ...group.skip(1).toList().reversed,
        ] else
          ...group.reversed,
    ];
  }

  double _extentOf(_Row row) => widget.chapters[row.index].isVolume
      ? _volumeExtent
      : row.index == widget.current
      ? _currentExtent
      : _chapterExtent;

  /// 当前章那一行往上留 [rowsAbove] 行的滚动位置。
  double _offsetOfCurrent({required int rowsAbove}) {
    final at = _rows.indexWhere((row) => row.index == widget.current);
    if (at < 0) return 0;
    var offset = 0.0;
    for (var i = 0; i < at - rowsAbove; i++) {
      offset += _extentOf(_rows[i]);
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final current = widget.current;
    final progress = _total == 0 ? 0.0 : _currentOrdinal / _total;
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Night.bg,
        body: StreamBuilder<Set<String>>(
          stream: ref.watch(databaseProvider).watchCachedChapterUrls(book.bookUrl),
          builder: (context, snapshot) {
            final cached = snapshot.data ?? const {};
            return Stack(
              children: [
                _Backdrop(url: book.coverUrl),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, padding.top + 12, 20, 0),
                      child: _Header(book: book, total: _total, cached: cached.length),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        spacing: 8,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _currentOrdinal == 0 ? '还没开始读' : '读到第 $_currentOrdinal 章',
                                  style: sans(12, color: Night.amber, weight: FontWeight.w600),
                                ),
                              ),
                              Text('${(progress * 100).floor()}%', style: sans(12, color: Night.text2)),
                            ],
                          ),
                          ThinProgress(value: progress),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        children: [
                          const _Tabs(),
                          const Spacer(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _reversed = !_reversed;
                              _rows = _build(reversed: _reversed);
                              _controller.jumpTo(0);
                            }),
                            child: Row(
                              spacing: 4,
                              children: [
                                const Icon(LucideIcons.arrowDownUp, size: 14, color: Night.text2),
                                Text(_reversed ? '倒序' : '正序', style: sans(13, color: Night.text2)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        controller: _controller,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _rows.length,
                        itemExtentBuilder: (index, _) => index < _rows.length ? _extentOf(_rows[index]) : null,
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final chapter = widget.chapters[row.index];
                          if (chapter.isVolume) return _VolumeHeader(title: chapter.title, first: row.ordinal, last: row.last);
                          return _ChapterRow(
                            ordinal: row.ordinal!,
                            title: chapter.title,
                            read: current != null && row.index < current,
                            current: row.index == current,
                            cached: cached.contains(chapter.url),
                            onTap: () => Navigator.pop(context, row.index),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, padding.bottom + 16),
                      child: Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: PillButton(
                              icon: LucideIcons.locateFixed,
                              iconSize: 17,
                              fontSize: 15,
                              padding: 12,
                              label: '定位当前',
                              onPressed: current == null
                                  ? null
                                  : () => _controller.animateTo(
                                      _offsetOfCurrent(rowsAbove: 3).clamp(0, _controller.position.maxScrollExtent),
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    ),
                            ),
                          ),
                          Expanded(
                            child: PillButton(
                              primary: false,
                              icon: LucideIcons.download,
                              iconSize: 17,
                              padding: 12,
                              label: '缓存后续 50 章',
                              onPressed: () => showNotDeveloped(context, '缓存后续章节'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 顶部的模糊封面，往下渐隐到底色。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: -40,
      right: -40,
      top: -40,
      height: 330,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ClipRect(
          child: Opacity(
            opacity: 0.6,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.book, required this.total, required this.cached});

  final ShelfBook book;
  final int total;
  final int cached;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    spacing: 16,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x1AFFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0xB3000000), offset: Offset(0, 10), blurRadius: 20)],
        ),
        child: BookCover(url: book.coverUrl, title: book.name, width: 64, height: 92, radius: 6),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: Night.text2, weight: FontWeight.w600),
            ),
            Text('目录', style: serif(32, letterSpacing: 2, height: 1.2)),
            Text('共 $total 章 · 已缓存 $cached 章', style: sans(12, color: Night.text3)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: GlassIconButton(icon: LucideIcons.x, tooltip: '关闭', onPressed: () => Navigator.pop(context)),
      ),
    ],
  );
}

/// 目录、书签、笔记三个页签：书签和笔记还没做。
class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, {bool selected = false, VoidCallback? onTap}) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: selected ? Night.text : null),
        child: Text(
          label,
          style: sans(13, color: selected ? Night.bg : Night.text2, weight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Night.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Night.line),
      ),
      child: Row(
        spacing: 6,
        children: [
          tab('目录', selected: true),
          tab('书签', onTap: () => showNotDeveloped(context, '书签')),
          tab('笔记', onTap: () => showNotDeveloped(context, '笔记')),
        ],
      ),
    );
  }
}

/// 组件库「Volume Header」：「第三卷 雪城」拆成卷序号和卷名，右边是章节范围。
class _VolumeHeader extends StatelessWidget {
  const _VolumeHeader({required this.title, required this.first, required this.last});

  static final _numbered = RegExp(r'^(第\S{1,8}?卷)\s*(.*)$');

  final String title;
  final int? first;
  final int? last;

  @override
  Widget build(BuildContext context) {
    final match = _numbered.firstMatch(title.trim());
    final (label, name) = match != null && match[2]!.isNotEmpty ? (match[1], match[2]!) : (null, title);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 10,
        children: [
          if (label != null)
            Text(
              label,
              style: sans(12, color: Night.text3, weight: FontWeight.w700, letterSpacing: 2),
            ),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(20, height: 1.3)),
          ),
          if (first != null) Text('第 $first – $last 章', style: sans(11, color: Night.text3)),
        ],
      ),
    );
  }
}

/// 组件库「Chapter Row」：序号、章节名；读过的变暗，已缓存的打勾，没缓存的是下载图标，当前章是高亮卡片。
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.ordinal,
    required this.title,
    required this.read,
    required this.current,
    required this.cached,
    required this.onTap,
  });

  final int ordinal;
  final String title;
  final bool read;
  final bool current;
  final bool cached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      spacing: 12,
      children: [
        SizedBox(
          width: 40,
          child: Text('$ordinal', maxLines: 1, style: serif(17, color: current ? Night.amber : (read ? Night.dim : Night.text3))),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(15, color: read && !current ? Night.text3 : Night.text, weight: current ? FontWeight.w700 : FontWeight.w400),
          ),
        ),
        if (current)
          const AmberTag('读到这里')
        else
          Icon(cached ? LucideIcons.check : LucideIcons.cloudDownload, size: 15, color: read ? Night.dim : Night.text3),
      ],
    );
    if (current) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: Night.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x40F0B357)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: row),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Night.line)),
        ),
        child: row,
      ),
    );
  }
}
