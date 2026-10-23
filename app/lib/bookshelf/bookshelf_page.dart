import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../online/book_detail_page.dart';
import '../online/search_page.dart';
import '../online/source_list_page.dart';
import '../reader/reader_page.dart';
import '../settings/settings_page.dart';
import '../storage/database.dart';
import 'shelf_refresh.dart';

/// 书架（bookshelf）：点击继续阅读，下拉刷新更新目录。
class BookshelfPage extends ConsumerWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    final refresh = ref.watch(shelfRefreshProvider);
    final controller = ref.read(shelfRefreshProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          // 桌面上用鼠标不方便下拉，和下拉刷新是同一个操作
          IconButton(
            tooltip: '更新目录',
            icon: const Icon(Icons.refresh),
            onPressed: refresh.running || shelf.isEmpty ? null : controller.refresh,
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          ),
          IconButton(
            tooltip: '书源',
            icon: const Icon(Icons.source_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourceListPage())),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (refresh.running) ...[
            LinearProgressIndicator(value: refresh.total == 0 ? null : refresh.done / refresh.total),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(child: Text('正在更新目录 ${refresh.done}/${refresh.total}')),
                TextButton(onPressed: controller.stop, child: const Text('停止')),
              ],
            ),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: shelf.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: Text('书架是空的，去搜索添加吧')))],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: shelf.length,
                      itemBuilder: (context, index) => _ShelfTile(entry: shelf[index], mark: refresh.marks[shelf[index].book.bookUrl]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfTile extends ConsumerWidget {
  const _ShelfTile({required this.entry, required this.mark});

  final ShelfEntry entry;

  /// 本次更新失败或书源不存在的原因。
  final String? mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = entry.book;
    final theme = Theme.of(context);
    final mark = this.mark;
    return ListTile(
      leading: BookCover(url: book.coverUrl, width: 40),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([book.author, ?book.latestChapterTitle].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (mark != null)
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mark))),
              child: Text(
                mark == '书源不存在' ? mark : '更新失败',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.unread > 0) Badge(label: Text('${entry.unread}')),
          PopupMenuButton<_Action>(
            tooltip: '更多',
            onSelected: (action) => switch (action) {
              _Action.detail => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => BookDetailPage.shelf(book.bookUrl)),
              ),
              _Action.remove => _remove(context, ref, book),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Action.detail, child: Text('详情')),
              PopupMenuItem(value: _Action.remove, child: Text('移出书架')),
            ],
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(bookUrl: book.bookUrl))),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, ShelfBook book) async {
    final db = ref.read(databaseProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('把《${book.name}》移出书架？'),
        content: const Text('目录、已缓存的正文和阅读进度会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移出')),
        ],
      ),
    );
    if (confirmed == true) await db.removeBook(book.bookUrl);
  }
}

enum _Action { detail, remove }
