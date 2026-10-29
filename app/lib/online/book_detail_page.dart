import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../reader/reader_page.dart';
import '../reader/toc_page.dart';
import '../storage/database.dart';
import '../ui/icons.dart';
import '../ui/tokens.dart';
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
    if (bookUrl == null) return _page(_display(), null);
    return StreamBuilder<ShelfBook?>(
      stream: _db.watchBook(bookUrl),
      builder: (context, snapshot) {
        final book = snapshot.data;
        if (book == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        return StreamBuilder<List<TocChapter>>(
          stream: _db.watchChapters(bookUrl),
          builder: (context, chapters) => _page(_displayOf(book), (book: book, chapters: chapters.data ?? const [])),
        );
      },
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

  /// 详情页（redesign-minimal-ui 设计 D3）：封面和书名、书源卡片、简介、目录入口，目录加载好以后底部固定加入书架和阅读两个按钮。
  Widget _page(_Display display, ({ShelfBook book, List<TocChapter> chapters})? saved) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final infoError = _infoError;
    final tocError = _tocError;
    final meta = [?display.kind, ?display.wordCount].where((text) => text.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: saved == null ? null : _actions(saved.book, saved.chapters),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.section),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(url: display.cover, width: 88, title: display.name),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(display.name, style: textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
                    if (display.author.isNotEmpty) Text(display.author, style: TextStyle(color: colors.textSecondary)),
                    if (meta.isNotEmpty) Text(meta, style: textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          _sourceCard(display.originName),
          if (display.intro case final intro? when intro.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.section),
            Text('简介', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            _Intro(intro),
          ],
          const SizedBox(height: AppSpacing.section),
          if (infoError != null)
            _Retry(message: infoError, onRetry: () => _loadInfo(_load))
          else if (saved != null)
            _tocEntry(saved.book, saved.chapters)
          else if (tocError != null)
            _Retry(message: tocError, onRetry: () => _loadToc(_load))
          else if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  /// 书源卡片：从搜索结果打开、有多个书源时点了选书源；从书架打开时点了进入换书源（book-detail「换书源」）。
  Widget _sourceCard(String originName) {
    final colors = AppColors.of(context);
    final (action, onTap) = switch (widget.bookUrl) {
      String() => ('换书源', _changeShelfSource),
      null when widget.candidates.length > 1 => ('共 ${widget.candidates.length} 个书源', _chooseSource),
      null => (null, null),
    };
    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(originName, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (action != null) ...[
                Text(action, style: TextStyle(color: colors.textSecondary)),
                Icon(LucideIcons.chevronRight, size: 18, color: colors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tocEntry(ShelfBook book, List<TocChapter> chapters) {
    final colors = AppColors.of(context);
    final latest = book.latestChapterTitle;
    return InkWell(
      onTap: () => _openToc(book, chapters),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text('目录', style: Theme.of(context).textTheme.titleMedium),
                  if (latest != null)
                    Text(latest, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textSecondary)),
                ],
              ),
            ),
            Text('共 ${chapters.where((c) => !c.isVolume).length} 章', style: TextStyle(color: colors.textSecondary)),
            Icon(LucideIcons.chevronRight, size: 18, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// 底部固定的两个按钮。有阅读进度时是「继续阅读」，从进度继续；没有时是「开始阅读」，从第一个不是卷的章节开始。
  Widget _actions(ShelfBook book, List<TocChapter> chapters) {
    final hasProgress = book.durChapterUrl != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 8),
        child: Row(
          spacing: AppSpacing.item,
          children: [
            Expanded(
              child: FillButton(
                onPressed: book.inShelf ? null : () => _db.addToShelf(book.bookUrl, DateTime.now()),
                child: Text(book.inShelf ? '已在书架' : '加入书架'),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: () => _read(book, startAt: hasProgress ? null : chapters.indexWhere((c) => !c.isVolume).clamp(0, chapters.length)),
                child: Text(hasProgress ? '继续阅读' : '开始阅读'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openToc(ShelfBook book, List<TocChapter> chapters) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => TocPage(
          bookUrl: book.bookUrl,
          bookName: book.name,
          chapters: chapters,
          current: book.durChapterUrl == null ? null : book.durChapterIndex,
        ),
      ),
    );
    if (index != null && mounted) _read(book, startAt: index);
  }

  void _read(ShelfBook book, {int? startAt}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(bookUrl: book.bookUrl, startAt: startAt)));

  /// 换源成功后改为显示新书；旧书已从数据库删除。
  Future<void> _changeShelfSource() async {
    final bookUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ChangeSourcePage(bookUrl: _bookUrl!)),
    );
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
                trailing: i == _current ? Icon(LucideIcons.check, color: AppColors.of(context).accent) : null,
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
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(message, style: TextStyle(color: AppColors.of(context).danger)),
        const SizedBox(height: 8),
        FillButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

/// 简介：默认最多显示四行，超出时末尾有「展开」，展开后是「收起」。
class _Intro extends StatefulWidget {
  const _Intro(this.text);

  final String text;

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> {
  static const _collapsedLines = 4;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = DefaultTextStyle.of(context).style.copyWith(color: colors.textSecondary, height: 1.6);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_expanded ? '收起' : '展开', style: TextStyle(color: colors.accent)),
                ),
              ),
          ],
        );
      },
    );
  }
}
