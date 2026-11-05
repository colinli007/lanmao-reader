import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../storage/database.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'book_cache.dart';
import 'shelf_refresh.dart';

/// 每本书不是卷的章节总数和已缓存的章数（缓存管理页）。
final cacheCountsProvider = StreamProvider.autoDispose<Map<String, BookCacheCount>>(
  (ref) => ref.watch(databaseProvider).watchCacheCounts(),
);

/// 发起缓存（book-cache「发起缓存」，add-book-cache 设计 D4）：说明总章数和已缓存章数，选「从当前章往后」或「全部章节」；
/// 整本都已缓存时提示，不弹选择。返回是否开始了缓存。书架和缓存管理页共用。
Future<bool> chooseCacheRange(BuildContext context, WidgetRef ref, ShelfBook book) async {
  final controller = ref.read(bookCacheProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final plan = await controller.plan(book);
  if (!context.mounted) return false;
  if (plan.pending[CacheRange.all]!.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('已经全部缓存')));
    return false;
  }
  final range = await showActionSheet<CacheRange>(
    context,
    message: '共 ${plan.total} 章，已缓存 ${plan.cached} 章',
    items: [
      for (final (range, label) in [(CacheRange.fromCurrent, '从当前章往后'), (CacheRange.all, '全部章节')])
        if (plan.pending[range]!.isNotEmpty) (value: range, label: '$label（${plan.pending[range]!.length} 章）', danger: false),
    ],
  );
  if (range == null) return false;
  await controller.start(book, range);
  return true;
}

/// 缓存管理页（book-cache「缓存管理页」，add-book-cache 设计 D5）：书架上每本书的已缓存章数，缓存中的进度和停止，发起缓存。
class CachePage extends ConsumerWidget {
  const CachePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    final counts = ref.watch(cacheCountsProvider).valueOrNull ?? const {};
    final progress = ref.watch(bookCacheProvider);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('缓存管理')),
      body: shelf.isEmpty
          ? Center(child: Text('书架是空的', style: TextStyle(color: colors.textSecondary)))
          : ListView(
              children: [
                for (final (:book, unread: _) in shelf)
                  _CacheTile(book: book, count: counts[book.bookUrl], progress: progress[book.bookUrl]),
              ],
            ),
    );
  }
}

class _CacheTile extends ConsumerWidget {
  const _CacheTile({required this.book, required this.count, required this.progress});

  final ShelfBook book;
  final BookCacheCount? count;
  final BookCacheProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final progress = this.progress;
    final running = progress?.running ?? false;
    final failed = progress == null || progress.failed == 0 ? null : '失败 ${progress.failed} 章';
    final status = [
      if (count case (:final cached, :final total)) '已缓存 $cached / $total 章',
      if (running) '缓存中 ${progress!.done} / ${progress.total}',
      if (failed != null) running ? failed : '上次$failed',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(status, style: TextStyle(color: failed != null ? colors.danger : colors.textSecondary, fontSize: 13)),
      trailing: running
          ? TextButton(onPressed: () => ref.read(bookCacheProvider.notifier).stop(book.bookUrl), child: const Text('停止'))
          : TextButton(onPressed: () => chooseCacheRange(context, ref, book), child: const Text('缓存')),
    );
  }
}
