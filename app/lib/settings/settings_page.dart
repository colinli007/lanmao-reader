import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../storage/database.dart';
import 'about_page.dart';
import 'byte_size.dart';

/// 进入设置页时统计，离开就丢掉（设计 D3）：设置页和阅读页不会同时打开，统计期间缓存不会变。
final contentCacheStatsProvider = FutureProvider.autoDispose<ContentCacheStats>(
  (ref) => ref.read(databaseProvider).contentCacheStats(),
);

/// 设置页（settings）：正文缓存和关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _ContentCacheTile(),
          ListTile(
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
    );
  }
}

/// 「正文缓存」项：章节数和大小，清除（settings「清除正文缓存的操作」）。
class _ContentCacheTile extends ConsumerStatefulWidget {
  const _ContentCacheTile();

  @override
  ConsumerState<_ContentCacheTile> createState() => _ContentCacheTileState();
}

class _ContentCacheTileState extends ConsumerState<_ContentCacheTile> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(contentCacheStatsProvider).valueOrNull;
    final clearable = stats != null && stats.chapters > 0 && !_clearing;
    return ListTile(
      title: const Text('正文缓存'),
      subtitle: Text(switch (stats) {
        _ when _clearing => '清除中',
        null => '统计中',
        (:final chapters, :final bytes) => '$chapters 章 · ${formatByteSize(bytes)}',
      }),
      trailing: TextButton(onPressed: clearable ? () => _clear(stats.chapters) : null, child: const Text('清除')),
    );
  }

  Future<void> _clear(int chapters) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除正文缓存？'),
        content: Text('会删除已缓存的 $chapters 章正文，之后阅读这些章节需要重新联网。书架、目录和阅读进度不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await ref.read(databaseProvider).clearContents();
    // 等重新统计完再收起「清除中」，中间不闪一下「统计中」
    ref.invalidate(contentCacheStatsProvider);
    await ref.read(contentCacheStatsProvider.future);
    if (mounted) setState(() => _clearing = false);
  }
}
