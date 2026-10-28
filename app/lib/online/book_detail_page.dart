import 'dart:ui';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../reader/reader_route.dart';
import '../reader/toc_page.dart';
import '../storage/database.dart';
import '../ui/cinema.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart';
import 'book_mapping.dart';
import 'change_source_page.dart';
import 'errors.dart';
import 'providers.dart';
import 'search_controller.dart';

/// 详情与目录（book-detail）。从搜索结果打开时依次执行详情、目录链路，目录加载完成后这本书作为浏览中的书落盘；
/// 书已经在书架上时直接显示书架上保存的信息。
class BookDetailPage extends ConsumerStatefulWidget {
  BookDetailPage.search(MergedBook merged, {super.key}) : candidates = merged.results, bookUrl = null;

  const BookDetailPage.shelf(String this.bookUrl, {super.key}) : candidates = const [];

  /// 合并项在各书源上的结果，按完成的先后。
  final List<SearchCandidate> candidates;

  /// 从书架打开时的书籍地址。
  final String? bookUrl;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  late final AppDatabase _db = ref.read(databaseProvider);

  int _current = 0;

  /// 已落盘（浏览中或在书架上）的书籍地址；有了它，界面显示数据库里的书和目录。
  String? _bookUrl;
  Book? _info;
  String? _infoError;
  String? _tocError;
  bool _loading = false;

  /// 每次开始加载加一，换书源之后丢掉旧的结果。
  int _load = 0;

  @override
  void initState() {
    super.initState();
    if (widget.bookUrl case final bookUrl?) {
      _bookUrl = bookUrl;
    } else {
      _open(0);
    }
  }

  SearchCandidate get _candidate => widget.candidates[_current];

  Future<void> _open(int index) async {
    final load = ++_load;
    setState(() {
      _current = index;
      _bookUrl = null;
      _info = null;
      _infoError = _tocError = null;
    });
    final stored = await _db.getBook(_candidate.book.bookUrl);
    if (!mounted || load != _load) return;
    if (stored != null && stored.inShelf) {
      setState(() => _bookUrl = stored.bookUrl);
      return;
    }
    await _loadInfo(load);
  }

  Future<void> _loadInfo(int load) async {
    setState(() {
      _loading = true;
      _infoError = null;
    });
    try {
      final info = await ref.read(sourceEngineProvider).bookInfo(_candidate.source.source, _candidate.book.toBook());
      if (!mounted || load != _load) return;
      setState(() => _info = info);
    } catch (e) {
      if (mounted && load == _load) {
        setState(() {
          _infoError = describeError(e);
          _loading = false;
        });
      }
      return;
    }
    await _loadToc(load);
  }

  Future<void> _loadToc(int load) async {
    setState(() {
      _loading = true;
      _tocError = null;
    });
    try {
      final result = await ref.read(sourceEngineProvider).chapterList(_candidate.source.source, _info!);
      final update = tocUpdateOf(result);
      final book = shelfBookOf(result.book).copyWith(latestChapterTitle: Value(update.latestChapterTitle));
      await _db.saveBrowsingBook(book, update.chapters);
      if (!mounted || load != _load) return;
      setState(() {
        _bookUrl = book.bookUrl;
        _loading = false;
      });
    } catch (e) {
      if (mounted && load == _load) {
        setState(() {
          _tocError = describeError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookUrl = _bookUrl;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Night.bg,
        body: Stack(
          children: [
            if (bookUrl == null)
              _body(_display(), null)
            else
              StreamBuilder<ShelfBook?>(
                stream: _db.watchBook(bookUrl),
                builder: (context, snapshot) {
                  final book = snapshot.data;
                  if (book == null) return const Center(child: CircularProgressIndicator());
                  return StreamBuilder<List<TocChapter>>(
                    stream: _db.watchChapters(bookUrl),
                    builder: (context, chapters) => _body(_displayOf(book), (book: book, chapters: chapters.data ?? const [])),
                  );
                },
              ),
            const StatusBarScrim(),
          ],
        ),
      ),
    );
  }

  /// 没落盘之前：详情链路的结果，没有时用搜索结果。
  _Display _display() {
    final info = _info;
    if (info != null) {
      return (
        name: info.name,
        author: info.author,
        kind: info.kind,
        wordCount: info.wordCount,
        intro: info.intro,
        latest: info.latestChapterTitle,
        cover: info.coverUrl,
        originName: info.originName,
      );
    }
    final book = _candidate.book;
    return (
      name: book.name,
      author: book.author,
      kind: book.kind,
      wordCount: book.wordCount,
      intro: book.intro,
      latest: book.latestChapterTitle,
      cover: book.coverUrl,
      originName: book.originName,
    );
  }

  _Display _displayOf(ShelfBook book) => (
    name: book.name,
    author: book.author,
    kind: book.kind,
    wordCount: book.wordCount,
    intro: book.intro,
    latest: book.latestChapterTitle,
    cover: book.coverUrl,
    originName: book.originName,
  );

  Widget _body(_Display display, ({ShelfBook book, List<TocChapter> chapters})? saved) {
    final padding = MediaQuery.paddingOf(context);
    final readable = saved == null
        ? null
        : [
            for (final (i, c) in saved.chapters.indexed)
              if (!c.isVolume) i,
          ];
    final kinds = display.kind?.split(RegExp(r'[,，、/|\s]+')).where((k) => k.isNotEmpty).toList() ?? const <String>[];
    // 背景跟着内容一起滚动
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom + 40),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _Backdrop(url: display.cover, top: -40 - padding.top),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassIconButton(
                      icon: LucideIcons.chevronLeft,
                      iconSize: 20,
                      tooltip: '返回',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    GlassIconButton(
                      icon: LucideIcons.ellipsis,
                      iconSize: 20,
                      tooltip: '更多',
                      onPressed: () => showNotDeveloped(context, '更多操作'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x1AFFFFFF)),
                        boxShadow: const [BoxShadow(color: Color(0xB3000000), offset: Offset(0, 20), blurRadius: 40)],
                      ),
                      child: BookCover(url: display.cover, title: display.name, width: 150, height: 214, radius: 10),
                    ),
                    const SizedBox(height: 20),
                    Text(display.name, textAlign: TextAlign.center, style: serif(36, letterSpacing: 3, height: 1.25)),
                    const SizedBox(height: 8),
                    Text(
                      [display.author, ?kinds.firstOrNull].where((s) => s.isNotEmpty).join('  ·  '),
                      textAlign: TextAlign.center,
                      style: sans(13, color: Night.text2),
                    ),
                    const SizedBox(height: 20),
                    _Stats(wordCount: display.wordCount, chapters: readable?.length),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [_primary(saved, readable), _quickActions(saved)],
                ),
              ),
              if (display.intro case final intro? when intro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Text(intro.trim(), style: sans(14, color: Night.text2, height: 1.75)),
                ),
              if (kinds.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [for (final kind in kinds.skip(1)) OutlineTag(kind)]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SectionHead(
                        title: '最新章节',
                        meta: display.originName,
                        link: readable == null ? '目录' : '目录 ${readable.length}',
                        onLink: saved == null ? () {} : () => _openToc(saved.book, saved.chapters),
                      ),
                    ),
                    if (saved != null && readable != null)
                      for (final ordinal in [for (var i = readable.length; i > 0 && i > readable.length - 3; i--) i])
                        _LatestRow(
                          ordinal: ordinal,
                          title: saved.chapters[readable[ordinal - 1]].title,
                          unread: saved.book.durChapterUrl != null && readable[ordinal - 1] > saved.book.durChapterIndex,
                          onTap: () => _read(saved.book, startAt: readable[ordinal - 1]),
                        )
                    else if (_tocError case final error?)
                      _Retry(message: error, onRetry: () => _loadToc(_load))
                    else if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 主按钮：有进度时「继续阅读 · 第 N 章」，没有时「开始阅读」；详情失败时换成错误原因和重试。
  Widget _primary(({ShelfBook book, List<TocChapter> chapters})? saved, List<int>? readable) {
    if (_infoError case final error?) return _Retry(message: error, onRetry: () => _loadInfo(_load));
    if (saved == null || readable == null) {
      return const PillButton(icon: null, label: '目录加载中', height: 52, onPressed: null);
    }
    final book = saved.book;
    final started = book.durChapterUrl != null;
    return PillButton(
      icon: LucideIcons.play,
      height: 52,
      label: started ? '继续阅读 · 第 ${readable.where((i) => i <= book.durChapterIndex).length} 章' : '开始阅读',
      onPressed: readable.isEmpty
          ? null
          // 有进度从进度继续，没有时从第一个不是卷的章节开始
          : () => _read(book, startAt: started ? null : readable.first),
    );
  }

  Widget _quickActions(({ShelfBook book, List<TocChapter> chapters})? saved) {
    final inShelf = saved?.book.inShelf ?? false;
    final candidates = widget.candidates.length;
    return Row(
      children: [
        Expanded(
          child: inShelf
              ? QuickAction(icon: LucideIcons.check, label: '已在书架', color: Night.amber, labelColor: Night.amber, onTap: () {})
              : QuickAction(
                  icon: LucideIcons.plus,
                  label: '加入书架',
                  color: saved == null ? Night.text3 : null,
                  onTap: saved == null ? () {} : () => _db.addToShelf(saved.book.bookUrl, DateTime.now()),
                ),
        ),
        Expanded(
          child: QuickAction(icon: LucideIcons.download, label: '缓存', onTap: () => showNotDeveloped(context, '缓存全本')),
        ),
        Expanded(
          child: QuickAction(
            icon: LucideIcons.repeat,
            label: candidates > 1 ? '换源 $candidates' : '换源',
            onTap: () {
              // 从书架打开：进入书架的换书源（book-detail「换书源」）；从搜索结果打开：在合并项的书源之间换
              if (widget.bookUrl != null) {
                _changeShelfSource();
              } else if (candidates > 1) {
                _chooseSource();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('搜索结果里只有这一个书源')));
              }
            },
          ),
        ),
        Expanded(
          child: QuickAction(icon: LucideIcons.share, label: '分享', onTap: () => showNotDeveloped(context, '分享')),
        ),
      ],
    );
  }

  Future<void> _openToc(ShelfBook book, List<TocChapter> chapters) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => TocPage(book: book, chapters: chapters, current: book.durChapterUrl == null ? null : book.durChapterIndex),
      ),
    );
    if (index != null && mounted) _read(book, startAt: index);
  }

  void _read(ShelfBook book, {int? startAt}) =>
      openReader(context, bookUrl: book.bookUrl, startAt: startAt, coverUrl: book.coverUrl, title: book.name);

  /// 换源成功后改为显示新书；旧书已从数据库删除。
  Future<void> _changeShelfSource() async {
    final bookUrl = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ChangeSourcePage(bookUrl: _bookUrl!)));
    if (bookUrl != null && mounted) setState(() => _bookUrl = bookUrl);
  }

  Future<void> _chooseSource() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (i, candidate) in widget.candidates.indexed)
              ListTile(
                title: Text(candidate.source.source.bookSourceName),
                subtitle: candidate.book.latestChapterTitle == null ? null : Text(candidate.book.latestChapterTitle!),
                selected: i == _current,
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != _current) await _open(chosen);
  }
}

typedef _Display = ({
  String name,
  String author,
  String? kind,
  String? wordCount,
  String? intro,
  String? latest,
  String? cover,
  String originName,
});

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      spacing: 12,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: sans(13, color: Night.bad),
        ),
        SizedBox(
          width: 140,
          child: PillButton(icon: LucideIcons.rotateCw, label: '重试', height: 40, iconSize: 16, fontSize: 14, onPressed: onRetry),
        ),
      ],
    ),
  );
}

/// 模糊的封面铺在顶部做背景，往下渐隐到底色。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url, required this.top});

  final String? url;

  /// 相对内容顶部的位置：比屏幕顶部再高 40，模糊的边缘不露出来。
  final double top;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: -40,
      right: -40,
      top: top,
      height: 560,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.5, 1],
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ClipRect(
          child: Opacity(
            opacity: 0.75,
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

/// 字数、章节、书友评分三项统计。书友评分没有数据来源，显示「—」。
class _Stats extends StatelessWidget {
  const _Stats({required this.wordCount, required this.chapters});

  final String? wordCount;
  final int? chapters;

  /// 「86.4万字」「123456字」这样的字数拆成数值和单位；看不懂的原样显示。
  static final _count = RegExp(r'^\s*([\d.]+)\s*(万|千)?\s*字?\s*$');

  @override
  Widget build(BuildContext context) {
    final words = _words(wordCount);
    Widget divider() => Container(width: 1, height: 28, color: Night.line);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _Stat(value: words.$1, unit: words.$2, label: '字数'),
          ),
          divider(),
          Expanded(
            child: _Stat(value: chapters == null ? '—' : '$chapters', label: '章节'),
          ),
          divider(),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showNotDeveloped(context, '书友评分'),
              child: const _Stat(value: '—', label: '书友评分'),
            ),
          ),
        ],
      ),
    );
  }

  static (String, String?) _words(String? text) {
    if (text == null || text.trim().isEmpty) return ('—', null);
    final match = _count.firstMatch(text);
    if (match == null) return (text.trim(), null);
    final number = double.tryParse(match[1]!);
    if (match[2] == null && number != null && number >= 10000) return ((number / 10000).toStringAsFixed(1), '万');
    return (match[1]!, match[2]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, this.unit, required this.label});

  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 4,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: 2,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(20, weight: FontWeight.w800),
            ),
          ),
          if (unit case final unit?) Text(unit, style: sans(12, color: Night.text2)),
        ],
      ),
      Text(label, style: sans(11, color: Night.text3)),
    ],
  );
}

/// 最新章节的一行：序号、章节名；还没读到的标「NEW」。
class _LatestRow extends StatelessWidget {
  const _LatestRow({required this.ordinal, required this.title, required this.unread, required this.onTap});

  final int ordinal;
  final String title;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Night.line)),
      ),
      child: Row(
        spacing: 14,
        children: [
          SizedBox(
            width: 46,
            child: Text('$ordinal', maxLines: 1, style: serif(24, color: Night.text3)),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(15, weight: FontWeight.w600),
            ),
          ),
          if (unread) const AmberTag('NEW', height: 20, letterSpacing: 1, weight: FontWeight.w800),
        ],
      ),
    ),
  );
}
