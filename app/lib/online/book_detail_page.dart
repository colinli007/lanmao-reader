import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../reader/chapter_list.dart';
import '../reader/reader_page.dart';
import '../storage/database.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('详情')),
      body: bookUrl == null
          ? _body(_display(), null)
          : StreamBuilder<ShelfBook?>(
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
    final theme = Theme.of(context);
    final infoError = _infoError;
    final tocError = _tocError;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(url: display.cover, width: 90),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display.name, style: theme.textTheme.titleLarge),
                  if (display.author.isNotEmpty) Text(display.author),
                  if (display.kind case final kind? when kind.isNotEmpty) Text(kind, style: theme.textTheme.bodySmall),
                  if (display.wordCount case final count? when count.isNotEmpty) Text(count, style: theme.textTheme.bodySmall),
                  Text('书源：${display.originName}', style: theme.textTheme.bodySmall),
                  if (saved != null && saved.book.inShelf) Text('已在书架', style: TextStyle(color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
        if (widget.candidates.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: Text('换书源（共 ${widget.candidates.length} 个）'),
              onPressed: _chooseSource,
            ),
          ),
        // 从书架打开：进入书架的换书源（book-detail「换书源」）
        if (widget.bookUrl != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('换书源'), onPressed: _changeShelfSource),
          ),
        if (display.intro case final intro? when intro.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(intro)),
        if (infoError != null)
          _Retry(message: infoError, onRetry: () => _loadInfo(_load))
        else if (saved != null)
          ..._tocActions(saved.book, saved.chapters)
        else if (tocError != null)
          _Retry(message: tocError, onRetry: () => _loadToc(_load))
        else if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  List<Widget> _tocActions(ShelfBook book, List<TocChapter> chapters) => [
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('目录（${chapters.length} 章）'),
      subtitle: Text(book.latestChapterTitle ?? ''),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(book.name)),
            body: ChapterList(
              chapters: chapters,
              current: book.durChapterUrl == null ? null : book.durChapterIndex,
              onSelect: (index) => _read(book, startAt: index, replace: true),
            ),
          ),
        ),
      ),
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: book.inShelf ? null : () => _db.addToShelf(book.bookUrl, DateTime.now()),
            child: Text(book.inShelf ? '已在书架' : '加入书架'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => _read(
              book,
              // 有进度从进度继续，没有时从第一个不是卷的章节开始
              startAt: book.durChapterUrl == null ? chapters.indexWhere((c) => !c.isVolume).clamp(0, chapters.length) : null,
            ),
            child: const Text('开始阅读'),
          ),
        ),
      ],
    ),
  ];

  void _read(ShelfBook book, {int? startAt, bool replace = false}) {
    final route = MaterialPageRoute<void>(builder: (_) => ReaderPage(bookUrl: book.bookUrl, startAt: startAt));
    replace ? Navigator.of(context).pushReplacement(route) : Navigator.of(context).push(route);
  }

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
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
