import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../online/replace_rule_list_page.dart';
import '../online/source_log_page.dart';
import '../storage/database.dart';
import '../ui/cinema.dart';
import '../ui/icons.dart';
import 'about_page.dart';
import 'byte_size.dart';

/// 进入设置页时统计，离开就丢掉（设计 D3）：设置页和阅读页不会同时打开，统计期间缓存不会变。
final contentCacheStatsProvider = FutureProvider.autoDispose<ContentCacheStats>((ref) => ref.read(databaseProvider).contentCacheStats());

/// 「我的」（settings，底部 Tab 的最后一项）：替换净化规则、书源日志、正文缓存和关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Night.bg,
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, padding.top + 12, 20, padding.bottom + 16),
          children: [
            Text('我的', style: sans(22, weight: FontWeight.w800)),
            const SizedBox(height: 24),
            _Group(
              children: [
                _Item(icon: LucideIcons.wandSparkles, title: '替换净化规则', onTap: () => push(const ReplaceRuleListPage())),
                _Item(icon: LucideIcons.scrollText, title: '书源日志', onTap: () => push(const SourceLogPage())),
              ],
            ),
            const SizedBox(height: 16),
            const _Group(children: [_ContentCacheTile()]),
            const SizedBox(height: 16),
            _Group(
              children: [_Item(icon: LucideIcons.info, title: '关于', onTap: () => push(const AboutPage()))],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一组设置项：圆角卡片，项之间有分隔线。
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Night.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Night.line),
    ),
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[if (index > 0) const Divider(indent: 52), child],
      ],
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 20, color: Night.text2),
    title: Text(title, style: sans(15)),
    trailing: const Icon(LucideIcons.chevronRight, size: 18, color: Night.text3),
    onTap: onTap,
  );
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
      leading: const Icon(LucideIcons.hardDrive, size: 20, color: Night.text2),
      title: Text('正文缓存', style: sans(15)),
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
