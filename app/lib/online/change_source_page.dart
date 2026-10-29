import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../library/relocate.dart';
import '../storage/database.dart';
import '../ui/tokens.dart';
import 'book_mapping.dart';
import 'errors.dart';
import 'providers.dart';
import 'search_controller.dart';
import 'search_page.dart';

/// 换书源的搜索：和搜索页同一个控制器，另一个实例，两个页面同时在导航栈里时互不影响（设计 D2）。
final changeSourceSearchProvider = NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);

/// 换书源（bookshelf「换书源」）：用书名搜索，同名同作者的结果是候选；选中后执行详情和目录链路，
/// 成功时新书替换书架上的旧书，页面返回新书籍地址（设计 D1）。离开页面时搜索随控制器取消。
class ChangeSourcePage extends ConsumerStatefulWidget {
  const ChangeSourcePage({super.key, required this.bookUrl});

  final String bookUrl;

  @override
  ConsumerState<ChangeSourcePage> createState() => _ChangeSourcePageState();
}

class _ChangeSourcePageState extends ConsumerState<ChangeSourcePage> {
  late final AppDatabase _db = ref.read(databaseProvider);

  ShelfBook? _book;

  /// 书架上所有书的地址：这个页面上书架不会变，打开时读一次。
  Set<String> _shelf = const {};

  /// 正在换过去的候选；不为空时列表不能点。
  SearchCandidate? _changing;

  /// 换源失败的原因，按候选的书籍地址。
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final book = (await _db.getBook(widget.bookUrl))!;
    final shelf = {for (final entry in await _db.shelf()) entry.book.bookUrl};
    if (!mounted) return;
    setState(() {
      _book = book;
      _shelf = shelf;
    });
    ref.read(changeSourceSearchProvider.notifier).search(book.name);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final state = ref.watch(changeSourceSearchProvider);
    final controller = ref.read(changeSourceSearchProvider.notifier);
    final candidates = book == null
        ? const <SearchCandidate>[]
        : state.books.where((m) => m.name == book.name.trim() && m.author == book.author.trim()).firstOrNull?.results ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(book == null ? '换书源' : '换书源：${book.name}')),
      body: Column(
        children: [
          if (state.total > 0) SearchProgress(state: state, onStop: controller.stop, finished: '搜索结束，共 ${candidates.length} 个候选'),
          Expanded(
            child: state.noSources
                ? const Center(child: Text('没有可以搜索的书源，先去导入或启用书源'))
                : ListView.builder(itemCount: candidates.length, itemBuilder: (context, index) => _tile(candidates[index])),
          ),
        ],
      ),
    );
  }

  Widget _tile(SearchCandidate candidate) {
    final url = candidate.book.bookUrl;
    final mark = url == widget.bookUrl ? '当前' : (_shelf.contains(url) ? '已在书架' : null);
    final latest = candidate.book.latestChapterTitle;
    final error = _errors[url];
    return ListTile(
      title: Text(candidate.source.source.bookSourceName),
      subtitle: latest == null && error == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (latest != null) Text(latest, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (error != null) Text(error, style: TextStyle(color: AppColors.of(context).danger)),
              ],
            ),
      trailing: identical(candidate, _changing)
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : (mark == null ? null : Text(mark)),
      enabled: mark == null && _changing == null,
      onTap: () => _change(candidate),
    );
  }

  /// 执行详情和目录链路，按章节名对齐进度后替换书架上的书（设计 D4、D5）。中途离开页面时不写入。
  Future<void> _change(SearchCandidate candidate) async {
    setState(() {
      _changing = candidate;
      _errors.remove(candidate.book.bookUrl);
    });
    try {
      final engine = ref.read(sourceEngineProvider);
      final info = await engine.bookInfo(candidate.source.source, candidate.book.toBook());
      final result = await engine.chapterList(candidate.source.source, info);
      if (!mounted) return;
      final update = tocUpdateOf(result);
      final old = _book!;
      var book = shelfBookOf(result.book).copyWith(
        latestChapterTitle: Value(update.latestChapterTitle),
        inShelf: true,
        addedAt: Value(old.addedAt),
        lastReadAt: Value(old.lastReadAt),
      );
      // 没读过的书保持初始进度；保存进度时章节地址和章节名一起写入
      if (old.durChapterUrl != null) {
        final aligned = alignChapter(update.chapters, index: old.durChapterIndex, title: old.durChapterTitle!);
        final chapter = update.chapters[aligned.index];
        book = book.copyWith(
          durChapterIndex: aligned.index,
          durChapterUrl: Value(chapter.url),
          durChapterTitle: Value(chapter.title),
          durChapterPos: aligned.matched ? old.durChapterPos : 0,
        );
      }
      await _db.changeSource(old.bookUrl, book, update.chapters);
      if (mounted) Navigator.of(context).pop(book.bookUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[candidate.book.bookUrl] = describeError(e);
        _changing = null;
      });
    }
  }
}
