import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../online/replace_rule_list_page.dart';
import '../online/source_list_page.dart';
import '../storage/database.dart';
import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'about_page.dart';
import 'byte_size.dart';
import 'reader_settings_page.dart';

/// 进入设置页时统计，离开就丢掉（add-settings 设计 D3）：设置页和阅读页不会同时打开，统计期间缓存不会变。
/// 设置页只在设置 tab 选中时构建（redesign-minimal-ui 设计 D1），所以每次切过去都重新统计。
final contentCacheStatsProvider = FutureProvider.autoDispose<ContentCacheStats>(
  (ref) => ref.read(databaseProvider).contentCacheStats(),
);

/// 设置页（settings「设置页入口」，redesign-minimal-ui 设计 D7）：浅灰底上三组卡片。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget link(String title, Widget Function() page) => ListTile(
      title: Text(title),
      trailing: Icon(LucideIcons.chevronRight, size: 18, color: colors.textSecondary),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
    );
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      appBar: largeTitleAppBar(context, title: '设置', backgroundColor: colors.groupedBackground),
      body: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.item, bottom: AppSpacing.section),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.section),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                child: Image.asset(
                  'assets/images/lazy-cat-logo.png',
                  width: 72,
                  height: 72,
                  semanticLabel: '懒猫 Logo',
                ),
              ),
            ),
          ),
          SettingsGroup(
            children: [
              link('书源', () => const SourceListPage()),
              link('替换净化规则', () => const ReplaceRuleListPage()),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsGroup(children: [link('阅读设置', () => const ReaderSettingsPage()), const _ContentCacheTile()]),
          const SizedBox(height: AppSpacing.section),
          SettingsGroup(children: [link('关于', () => const AboutPage())]),
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
    final confirmed = await showConfirmDialog(
      context,
      title: '清除正文缓存？',
      message: '会删除已缓存的 $chapters 章正文，之后阅读这些章节需要重新联网。书架、目录和阅读进度不受影响。',
      confirmLabel: '清除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    await ref.read(databaseProvider).clearContents();
    // 等重新统计完再收起「清除中」，中间不闪一下「统计中」
    ref.invalidate(contentCacheStatsProvider);
    await ref.read(contentCacheStatsProvider.future);
    if (mounted) setState(() => _clearing = false);
  }
}
