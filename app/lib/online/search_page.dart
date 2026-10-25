import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import 'book_detail_page.dart';
import 'search_controller.dart';

/// 搜索页（book-search）。离开这一页时控制器被销毁，未完成的搜索随之取消。
class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '书名或作者', border: InputBorder.none),
          onSubmitted: controller.search,
        ),
      ),
      body: Column(
        children: [
          if (state.total > 0)
            SearchProgress(state: state, onStop: controller.stop, finished: '搜索结束，共 ${state.books.length} 本'),
          Expanded(
            child: state.noSources
                ? const Center(child: Text('没有可以搜索的书源，先去导入或启用书源'))
                : ListView.builder(
                    itemCount: state.books.length,
                    itemBuilder: (context, index) => _ResultTile(book: state.books[index]),
                  ),
          ),
        ],
      ),
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
    return Column(
      children: [
        if (state.running) LinearProgressIndicator(value: state.done / state.total),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.running ? '已完成 ${state.done}/${state.total} 个书源' : finished,
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
    return ListTile(
      leading: BookCover(url: first.coverUrl, width: 40),
      title: Text(book.name),
      subtitle: Text([book.author, if (latest != null && latest.isNotEmpty) latest].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${book.results.length} 个书源'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.search(book))),
    );
  }
}
