import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'book_detail_page.dart';
import 'search_controller.dart';

/// 搜索历史，[filter] 为空时是全部（book-search「搜索历史」）。
final searchHistoryProvider = StreamProvider.autoDispose.family<List<String>, String>(
  (ref, filter) => ref.watch(databaseProvider).watchSearchKeywords(filter),
);

/// 搜索页（book-search）。离开这一页时控制器被销毁，未完成的搜索随之取消。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _input = TextEditingController();

  /// 最后一次操作是改输入框（显示搜索历史）还是提交（显示结果），和 Legado 一样（add-search-history 设计 D2）。
  bool _typing = true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.page,
        // 胶囊形输入框，右边「取消」返回
        title: TextField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: '书名或作者',
            isDense: true,
            prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.textSecondary),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none),
          ),
          onChanged: (_) {
            controller.stop();
            setState(() => _typing = true);
          },
          onSubmitted: _search,
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: AppSpacing.page - 12),
        ],
      ),
      body: _typing
          ? _history(colors)
          : Column(
              children: [
                if (state.total > 0)
                  SearchProgress(state: state, onStop: controller.stop, finished: '搜索结束，共 ${state.books.length} 本'),
                Expanded(
                  child: state.noSources
                      ? Center(child: Text('没有可以搜索的书源，先去导入或启用书源', style: TextStyle(color: colors.textSecondary)))
                      : ListView.builder(
                          itemCount: state.books.length,
                          itemBuilder: (context, index) => _ResultTile(book: state.books[index]),
                        ),
                ),
              ],
            ),
    );
  }

  /// 提交一个词：记入搜索历史再搜索（设计 D3）；去掉首尾空白后为空时什么都不做。
  void _search(String input) {
    final key = input.trim();
    if (key.isEmpty) return;
    ref.read(databaseProvider).useSearchKeyword(key, DateTime.now());
    ref.read(searchControllerProvider.notifier).search(key);
    setState(() => _typing = false);
  }

  /// 点历史词：填进输入框并搜索。
  void _searchHistory(String word) {
    _input.value = TextEditingValue(text: word, selection: TextSelection.collapsed(offset: word.length));
    FocusScope.of(context).unfocus();
    _search(word);
  }

  /// 搜索历史：点一下搜索，长按删一条，「清除」确认后删全部；没有历史时不显示（设计 D4）。
  Widget _history(AppColors colors) {
    final words = ref.watch(searchHistoryProvider(_input.text.trim())).valueOrNull ?? const <String>[];
    if (words.isEmpty) return const SizedBox.shrink();
    final db = ref.read(databaseProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, AppSpacing.page),
      children: [
        Row(
          children: [
            Expanded(child: Text('搜索历史', style: TextStyle(color: colors.textSecondary, fontSize: 13))),
            TextButton(
              onPressed: () async {
                final confirmed = await showConfirmDialog(context, title: '清除搜索历史？', confirmLabel: '清除', danger: true);
                if (confirmed) await db.clearSearchKeywords();
              },
              child: const Text('清除'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in words)
              Material(
                color: colors.fill,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _searchHistory(word),
                  onLongPress: () => db.deleteSearchKeyword(word),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(word, style: TextStyle(color: colors.textPrimary)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 搜索进度：进行中显示完成数和停止，结束后显示 [finished]；有失败的书源时可以查看原因。换书源页面也用它。
class SearchProgress extends StatelessWidget {
  const SearchProgress({super.key, required this.state, required this.onStop, required this.finished});

  final SearchState state;
  final VoidCallback onStop;
  final String finished;

  @override
  Widget build(BuildContext context) {
    final failures = state.failures;
    final colors = AppColors.of(context);
    return Column(
      children: [
        if (state.running) LinearProgressIndicator(value: state.done / state.total, minHeight: 2),
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.page, right: AppSpacing.page - 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.running ? '已完成 ${state.done}/${state.total} 个书源' : finished,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              if (failures.isNotEmpty)
                TextButton(onPressed: () => _showFailures(context, failures), child: Text('失败 ${failures.length} 个')),
              if (state.running) TextButton(onPressed: onStop, child: const Text('停止')),
            ],
          ),
        ),
      ],
    );
  }

  void _showFailures(BuildContext context, List<SearchFailure> failures) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        children: [
          for (final failure in failures) ListTile(title: Text(failure.sourceName), subtitle: Text(failure.reason)),
        ],
      ),
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.book});

  final MergedBook book;

  @override
  Widget build(BuildContext context) {
    final first = book.first;
    final latest = first.latestChapterTitle;
    final colors = AppColors.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 4),
      leading: BookCover(url: first.coverUrl, width: 44),
      title: Text(book.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([book.author, if (latest != null && latest.isNotEmpty) latest].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${book.results.length} 个书源', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.search(book))),
    );
  }
}
