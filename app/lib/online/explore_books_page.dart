import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/book_cover.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'book_detail_page.dart';
import 'errors.dart';
import 'providers.dart';
import 'search_controller.dart';
import 'source_repository.dart';

/// 分类书籍页（explore「分类书籍页」，add-explore 设计 D6）：按页取一个分类的书，页脚出现时取下一页，没有新书时到底。
class ExploreBooksPage extends ConsumerStatefulWidget {
  const ExploreBooksPage({super.key, required this.entry, required this.kind});

  final SourceEntry entry;
  final ExploreKind kind;

  @override
  ConsumerState<ExploreBooksPage> createState() => _ExploreBooksPageState();
}

class _ExploreBooksPageState extends ConsumerState<ExploreBooksPage> {
  final List<SearchBook> _books = [];
  final Set<String> _bookUrls = {};
  int _page = 1;
  bool _loading = false;
  bool _end = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 取下一页：去掉已经有的书，没有新书时到底（Legado 的 `ExploreShowActivity`）。
  void _load() {
    if (_loading || _end) return;
    _loading = true;
    _error = null;
    ref.read(sourceEngineProvider).explore(widget.entry.source, widget.kind.url!, _page).then(
      (books) {
        if (!mounted) return;
        final fresh = [for (final book in books) if (_bookUrls.add(book.bookUrl)) book];
        setState(() {
          _loading = false;
          _books.addAll(fresh);
          if (fresh.isEmpty) {
            _end = true;
          } else {
            _page++;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = describeError(error);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.kind.title)),
    body: ListView.builder(
      itemCount: _books.length + 1,
      itemBuilder: (context, index) => index < _books.length ? _BookTile(entry: widget.entry, book: _books[index]) : _footer(context),
    ),
  );

  /// 页脚：出现时取下一页（第一页填不满屏幕时也会接着取）；在取时转圈，出错时显示原因和「重试」，到底时说明。
  Widget _footer(BuildContext context) {
    final colors = AppColors.of(context);
    if (!_loading && !_end && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_load);
      });
    }
    final error = _error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.section),
      child: Center(
        child: error != null
            ? Column(
                spacing: AppSpacing.item,
                children: [
                  Text(error, textAlign: TextAlign.center, style: TextStyle(color: colors.danger)),
                  FillButton(onPressed: () => setState(_load), child: const Text('重试')),
                ],
              )
            : _end
            // 第一页解析出 0 本多半是网站拦截或规则失效，而不是分类没书（fix-explore-compat 设计 D4）
            ? Text(
                _books.isEmpty ? '没有取到书，可能是网站拦截了请求，或者书源规则已经失效' : '没有更多了',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              )
            : const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

/// 一本书：封面、书名，作者和最新章节，最多 2 行简介；点了打开详情页，和从搜索结果打开一样。
class _BookTile extends StatelessWidget {
  const _BookTile({required this.entry, required this.book});

  final SourceEntry entry;
  final SearchBook book;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final latest = book.latestChapterTitle;
    final intro = book.intro?.trim() ?? '';
    return InkWell(
      onTap: () {
        final merged = MergedBook(book.name, book.author)..results.add((source: entry, book: book));
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.search(merged)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.item,
          children: [
            BookCover(url: book.coverUrl, width: 56),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [book.author, if (latest != null && latest.isNotEmpty) latest].where((part) => part.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  if (intro.isNotEmpty)
                    Text(intro, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
