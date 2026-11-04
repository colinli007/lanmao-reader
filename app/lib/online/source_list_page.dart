import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'import_text.dart';
import 'providers.dart';
import 'source_check.dart';
import 'source_import.dart';
import 'source_log_page.dart';
import 'source_repository.dart';

/// 书源管理：导入、筛选、启用与停用、多选批量操作、导出（source-management），校验（source-check）。
class SourceListPage extends ConsumerStatefulWidget {
  const SourceListPage({super.key});

  @override
  ConsumerState<SourceListPage> createState() => _SourceListPageState();
}

class _SourceListPageState extends ConsumerState<SourceListPage> {
  /// 子串筛选：校验结束时会被设成「失效」，所以是受控的（add-source-check 设计 D5）。
  final _filter = TextEditingController();

  /// 分组筛选：null 是全部，空字符串是未分组（拆分组时丢掉了空的，不会和真的分组重名），其它是分组名。
  String? _group;

  /// 多选模式下选中的书源地址；为 null 时不在多选模式。
  Set<String>? _selected;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(sourceRepositoryProvider);
    final check = ref.watch(sourceCheckProvider);
    ref.listen(sourceCheckProvider, _onCheckChanged);
    final colors = AppColors.of(context);
    final keyword = _filter.text.trim();
    final group = _group;
    final groups = {for (final entry in repository.entries) ...entry.groups}.toList()..sort();
    final hasUngrouped = repository.entries.any((entry) => entry.groups.isEmpty);
    final entries = [
      for (final entry in repository.entries)
        if ((keyword.isEmpty || _matches(entry.source, keyword)) &&
            switch (group) {
              null => true,
              '' => entry.groups.isEmpty,
              _ => entry.groups.contains(group),
            })
          entry,
    ];
    final enabled = repository.entries.where((entry) => entry.enabled).length;
    final selected = _selected;

    Widget chip(String label, String? value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: value == group ? colors.onAccent : colors.textPrimary)),
        selected: value == group,
        onSelected: (_) => setState(() => _group = value),
      ),
    );

    return Scaffold(
      appBar: selected == null ? _normalBar(repository) : _selectionBar(repository, selected, entries),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, AppSpacing.item),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.textSecondary),
                hintText: '按名字、地址、分组筛选',
                isDense: true,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // 没有任何分组时不显示分组筛选
          if (groups.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                children: [
                  chip('全部', null),
                  for (final name in groups) chip(name, name),
                  if (hasUngrouped) chip('未分组', ''),
                ],
              ),
            ),
          if (repository.entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.item, AppSpacing.page, 4),
              child: Text('已启用 $enabled / 共 ${repository.entries.length}', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ),
          if (check.running) _checkProgress(check, colors),
          Expanded(
            child: repository.entries.isEmpty
                ? Center(child: Text('还没有书源，点右上角导入', style: TextStyle(color: colors.textSecondary)))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) => _tile(repository, entries[index]),
                  ),
          ),
        ],
      ),
    );
  }

  AppBar _normalBar(SourceRepository repository) => AppBar(
    title: const Text('书源'),
    actions: [
      ImportMenuButton(onSelected: _import),
      IconButton(
        tooltip: '书源日志',
        icon: const Icon(LucideIcons.scrollText),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourceLogPage())),
      ),
      IconButton(tooltip: '导出全部', icon: const Icon(LucideIcons.share), onPressed: () => _export(repository, const {})),
    ],
  );

  AppBar _selectionBar(SourceRepository repository, Set<String> selected, List<SourceEntry> visible) => AppBar(
    leading: IconButton(tooltip: '退出多选', icon: const Icon(LucideIcons.x), onPressed: () => setState(() => _selected = null)),
    title: Text('已选 ${selected.length} 个'),
    actions: [
      IconButton(
        tooltip: '全选',
        icon: const Icon(LucideIcons.listChecks),
        onPressed: () => setState(() => _selected = {...selected, for (final entry in visible) entry.url}),
      ),
      IconButton(
        tooltip: '启用',
        icon: const Icon(LucideIcons.checkCircle2),
        onPressed: selected.isEmpty ? null : () => repository.setEnabled(selected, true),
      ),
      IconButton(
        tooltip: '停用',
        icon: const Icon(LucideIcons.ban),
        onPressed: selected.isEmpty ? null : () => repository.setEnabled(selected, false),
      ),
      IconButton(
        tooltip: '删除',
        icon: const Icon(LucideIcons.trash2),
        onPressed: selected.isEmpty ? null : () => _delete(repository, selected),
      ),
      // 不常用的收进「更多」，标题「已选 N 个」才放得下
      PopupMenuButton<_MoreAction>(
        tooltip: '更多',
        icon: const Icon(LucideIcons.ellipsisVertical),
        enabled: selected.isNotEmpty,
        onSelected: (action) => switch (action) {
          _MoreAction.check => _check(repository, selected),
          _MoreAction.export => _export(repository, selected),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _MoreAction.check, child: Text('校验')),
          PopupMenuItem(value: _MoreAction.export, child: Text('导出')),
        ],
      ),
    ],
  );

  Widget _tile(SourceRepository repository, SourceEntry entry) {
    final source = entry.source;
    final type = _typeLabels[source.bookSourceType];
    final selected = _selected;
    return ListTile(
      title: Text(source.bookSourceName.isEmpty ? source.bookSourceUrl : source.bookSourceName),
      subtitle: Text(type == null ? entry.url : '$type · ${entry.url}', maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: selected == null
          ? null
          : Checkbox(value: selected.contains(entry.url), onChanged: (_) => _toggleSelection(entry.url)),
      trailing: Switch(value: entry.enabled, onChanged: (value) => repository.setEnabled({entry.url}, value)),
      onTap: selected == null ? null : () => _toggleSelection(entry.url),
      onLongPress: () => setState(() => _selected = {...?selected, entry.url}),
    );
  }

  void _toggleSelection(String url) => setState(() {
    final selected = {...?_selected};
    if (!selected.remove(url)) selected.add(url);
    _selected = selected;
  });

  Future<void> _import(ImportFrom from) async {
    final repository = ref.read(sourceRepositoryProvider);
    try {
      final text = await readImportText(context, from, kind: '书源', hint: '单个书源对象或书源数组');
      if (text == null || !mounted) return;
      final preview = await previewImport(text, repository);
      if (!mounted) return;
      if (!await _confirm(preview)) return;
      await repository.import(preview.sources);
      _snack('已导入 ${preview.sources.length} 个书源');
    } on ImportException catch (e) {
      if (mounted) await showImportError(context, e);
    }
  }

  Future<bool> _confirm(ImportPreview preview) => showConfirmDialog(
    context,
    title: '导入书源',
    message: '新增 ${preview.added} 个，更新 ${preview.updated} 个，跳过 ${preview.skipped.length} 个',
    content: preview.skipped.isEmpty ? null : SkippedList(preview.skipped),
    confirmLabel: '导入',
    confirmEnabled: preview.sources.isNotEmpty,
  );

  Future<void> _export(SourceRepository repository, Set<String> urls) async {
    final count = urls.isEmpty ? repository.entries.length : urls.length;
    await Clipboard.setData(ClipboardData(text: repository.export(urls)));
    _snack('已复制 $count 个书源到剪贴板');
  }

  Future<void> _delete(SourceRepository repository, Set<String> urls) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除 ${urls.length} 个书源？',
      message: '书架上来自这些书源的书会保留。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed) return;
    await repository.delete(urls);
    setState(() => _selected = null);
  }

  /// 子串筛选匹配名字、地址、分组原文和注释，和 Legado 的书源搜索一致（source-management「书源列表」）。
  static bool _matches(BookSource source, String keyword) => [
    source.bookSourceName,
    source.bookSourceUrl,
    source.json['bookSourceGroup'],
    source.json['bookSourceComment'],
  ].any((field) => field is String && field.contains(keyword));

  Widget _checkProgress(SourceCheckState check, AppColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('校验中 ${check.done} / ${check.total}', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: check.done / check.total),
            ],
          ),
        ),
        TextButton(onPressed: () => ref.read(sourceCheckProvider.notifier).stop(), child: const Text('停止')),
      ],
    ),
  );

  /// 校验选中的书源（source-check「发起校验」）：先确认关键词，开始后退出多选。
  Future<void> _check(SourceRepository repository, Set<String> selected) async {
    if (ref.read(sourceCheckProvider).running) return _snack('正在校验，等完成后再试');
    final keyword = await showInputDialog(context, title: '校验书源', hint: '搜索用的关键词', initial: '我的');
    if (keyword == null || keyword.trim().isEmpty || !mounted) return;
    final sources = [for (final entry in repository.entries) if (selected.contains(entry.url)) entry.source];
    ref.read(sourceCheckProvider.notifier).start(sources, keyword.trim());
    setState(() => _selected = null);
  }

  /// 校验结束时有失效的书源、筛选框是空的，就筛出失效书源（Legado 的做法，设计 D5）。
  void _onCheckChanged(SourceCheckState? previous, SourceCheckState next) {
    if (previous?.running != true || next.running || next.invalid == 0 || _filter.text.trim().isNotEmpty) return;
    setState(() => _filter.text = '失效');
    _snack('发现有失效书源，已为您自动筛选');
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 多选栏「更多」菜单里的操作。
enum _MoreAction { check, export }

const _typeLabels = {
  BookSourceType.audio: '音频',
  BookSourceType.image: '图片',
  BookSourceType.file: '文件',
  BookSourceType.video: '视频',
};
