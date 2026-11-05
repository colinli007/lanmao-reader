import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'errors.dart';
import 'explore_kinds.dart';
import 'providers.dart';
import 'source_repository.dart';

/// 发现分类的键：书源地址和发现地址，发现地址变了（重新导入）就重新计算。
typedef ExploreKindsKey = ({String url, String exploreUrl});

/// 书源的发现分类（explore「展开书源的分类」，add-explore 设计 D3）：不自动释放，这次运行里每个书源只算一次；
/// 出错后由「重试」重新计算。
final exploreKindsProvider = FutureProvider.family<List<ExploreKind>, ExploreKindsKey>((ref, key) async {
  final entry = ref.read(sourceRepositoryProvider)[key.url];
  if (entry == null) return const [];
  return ref.read(sourceEngineProvider).exploreKinds(entry.source);
});

/// 发现 tab（explore，add-explore 设计 D5）：能发现的书源按导入顺序列出，可以按名称、分组筛选；点一个展开它的分类，同时只展开一个。
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  final _filter = TextEditingController();

  /// 展开的书源地址。
  String? _expanded;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final all = [for (final entry in ref.watch(sourceRepositoryProvider).entries) if (entry.explorable) entry];
    final query = _filter.text.trim().toLowerCase();
    final entries = [
      for (final entry in all)
        if (query.isEmpty || entry.source.bookSourceName.toLowerCase().contains(query) || entry.groups.any((g) => g.toLowerCase().contains(query)))
          entry,
    ];
    return Scaffold(
      appBar: largeTitleAppBar(context, title: '发现'),
      body: all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: Text('没有可以发现的书源，先在「设置 → 书源」里导入或启用', textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, AppSpacing.item),
                  child: TextField(
                    controller: _filter,
                    decoration: InputDecoration(
                      prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.textSecondary),
                      hintText: '筛选书源',
                      isDense: true,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final expanded = entry.url == _expanded;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                            title: Text(entry.source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Icon(expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight, size: 18, color: colors.textSecondary),
                            onTap: () => setState(() => _expanded = expanded ? null : entry.url),
                          ),
                          if (expanded) _Kinds(entry),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// 展开的书源下面：计算中转圈，出错时原因和「重试」，没有分类时说明，否则是分类排版。
class _Kinds extends ConsumerWidget {
  const _Kinds(this.entry);

  final SourceEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final key = (url: entry.url, exploreUrl: entry.source.exploreUrl!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page - ExploreKindMetrics.padding - ExploreKindMetrics.margin, 0, AppSpacing.page - ExploreKindMetrics.padding - ExploreKindMetrics.margin, AppSpacing.item),
      child: switch (ref.watch(exploreKindsProvider(key))) {
        AsyncData(value: final kinds) when kinds.isEmpty => _message(Text('没有分类', style: TextStyle(color: colors.textSecondary))),
        AsyncData(value: final kinds) => ExploreKindsView(entry: entry, kinds: kinds),
        AsyncError(:final error) => _message(
          Column(
            spacing: AppSpacing.item,
            children: [
              Text(describeError(error), textAlign: TextAlign.center, style: TextStyle(color: colors.danger)),
              FillButton(onPressed: () => ref.invalidate(exploreKindsProvider(key)), child: const Text('重试')),
            ],
          ),
        ),
        _ => _message(const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      },
    );
  }

  static Widget _message(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.item), child: Center(child: child));
}
