import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../online/book_detail_page.dart';
import '../online/change_source_page.dart';
import '../online/search_page.dart';
import '../reader/reader_page.dart';
import '../storage/database.dart';
import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'shelf_refresh.dart';

/// 书架（bookshelf）：封面宫格，点击继续阅读，长按打开选项单，下拉刷新更新目录（redesign-minimal-ui 设计 D3）。
class BookshelfPage extends ConsumerWidget {
  const BookshelfPage({super.key});

  /// 每本书最宽多少：手机竖屏上正好三列，宽窗口自动加列，封面宽度变化不大。
  static const _maxTileWidth = 140.0;
  static const _spacing = 16.0;

  /// 封面下面的文字区：间距、两行书名、一行状态。
  static const _captionHeight = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    final refresh = ref.watch(shelfRefreshProvider);
    final controller = ref.read(shelfRefreshProvider.notifier);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: largeTitleAppBar(
        context,
        title: '书架',
        actions: [
          // 桌面上用鼠标不方便下拉，和下拉刷新是同一个操作；手机上只有下拉
          if (defaultTargetPlatform == TargetPlatform.macOS)
            IconButton(
              tooltip: '更新目录',
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: refresh.running || shelf.isEmpty ? null : controller.refresh,
            ),
          IconButton(tooltip: '搜索', icon: const Icon(LucideIcons.search), onPressed: () => _openSearch(context)),
        ],
      ),
      body: Column(
        children: [
          if (refresh.running) ...[
            LinearProgressIndicator(value: refresh.total == 0 ? null : refresh.done / refresh.total, minHeight: 2),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.page, right: AppSpacing.page - 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('正在更新目录 ${refresh.done}/${refresh.total}', style: TextStyle(color: colors.textSecondary)),
                  ),
                  TextButton(onPressed: controller.stop, child: const Text('停止')),
                ],
              ),
            ),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: shelf.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text('书架还是空的', style: TextStyle(color: colors.textSecondary))),
                        const SizedBox(height: AppSpacing.item),
                        Center(child: FillButton(onPressed: () => _openSearch(context), child: const Text('去搜索'))),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth - AppSpacing.page * 2;
                        final columns = ((width + _spacing) / (_maxTileWidth + _spacing)).ceil();
                        final tileWidth = (width - _spacing * (columns - 1)) / columns;
                        return GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.item, AppSpacing.page, AppSpacing.section),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: _spacing,
                            mainAxisSpacing: AppSpacing.item,
                            mainAxisExtent: tileWidth * 4 / 3 + _captionHeight,
                          ),
                          itemCount: shelf.length,
                          itemBuilder: (context, index) => _ShelfTile(
                            entry: shelf[index],
                            mark: refresh.marks[shelf[index].book.bookUrl],
                            coverWidth: tileWidth,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
}

class _ShelfTile extends ConsumerWidget {
  const _ShelfTile({required this.entry, required this.mark, required this.coverWidth});

  final ShelfEntry entry;

  /// 本次更新失败或书源不存在的原因。
  final String? mark;

  final double coverWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = entry.book;
    final colors = AppColors.of(context);
    final mark = this.mark;
    final status = switch (mark) {
      null when entry.unread > 0 => Text('${entry.unread} 章未读', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      null => null,
      _ => Text(mark == '书源不存在' ? mark : '更新失败', style: TextStyle(color: colors.danger, fontSize: 12)),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(bookUrl: book.bookUrl))),
      onLongPress: () => _showActions(context, ref, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: book.coverUrl, width: coverWidth, title: book.name),
          const SizedBox(height: 8),
          Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 4),
          ?status,
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, ShelfBook book) async {
    final mark = this.mark;
    final action = await showActionSheet<_Action>(
      context,
      items: [
        if (mark != null) (value: _Action.failure, label: '失败原因', danger: false),
        (value: _Action.detail, label: '详情', danger: false),
        (value: _Action.changeSource, label: '换书源', danger: false),
        (value: _Action.remove, label: '移出书架', danger: true),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _Action.failure:
        await showMessageDialog(context, title: mark == '书源不存在' ? mark! : '更新失败', message: mark!);
      case _Action.detail:
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.shelf(book.bookUrl)));
      case _Action.changeSource:
        await _changeSource(context, ref, book);
      case _Action.remove:
        await _remove(context, ref, book);
    }
  }

  /// 换书源成功后书架跟着数据库刷新，这里只提示换到了哪个书源。
  Future<void> _changeSource(BuildContext context, WidgetRef ref, ShelfBook book) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final bookUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ChangeSourcePage(bookUrl: book.bookUrl)),
    );
    if (bookUrl == null) return;
    final changed = await db.getBook(bookUrl);
    messenger.showSnackBar(SnackBar(content: Text('已换到${changed!.originName}')));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, ShelfBook book) async {
    final db = ref.read(databaseProvider);
    final confirmed = await showConfirmDialog(
      context,
      title: '把《${book.name}》移出书架？',
      message: '目录、已缓存的正文和阅读进度会一起删除。',
      confirmLabel: '移出',
      danger: true,
    );
    if (confirmed) await db.removeBook(book.bookUrl);
  }
}

enum _Action { failure, detail, changeSource, remove }
