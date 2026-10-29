import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'import_text.dart';
import 'providers.dart';
import 'source_import.dart';
import 'source_log_page.dart';
import 'source_repository.dart';

/// 书源管理：导入、筛选、启用与停用、多选批量操作、导出（source-management）。
class SourceListPage extends ConsumerStatefulWidget {
  const SourceListPage({super.key});

  @override
  ConsumerState<SourceListPage> createState() => _SourceListPageState();
}

class _SourceListPageState extends ConsumerState<SourceListPage> {
  String _filter = '';

  /// 分组筛选：null 是全部，空字符串是未分组（拆分组时丢掉了空的，不会和真的分组重名），其它是分组名。
  String? _group;

  /// 多选模式下选中的书源地址；为 null 时不在多选模式。
  Set<String>? _selected;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(sourceRepositoryProvider);
    final colors = AppColors.of(context);
    final keyword = _filter.trim();
    final group = _group;
    final groups = {for (final entry in repository.entries) ...entry.groups}.toList()..sort();
    final hasUngrouped = repository.entries.any((entry) => entry.groups.isEmpty);
    final entries = [
      for (final entry in repository.entries)
        if ((keyword.isEmpty || entry.source.bookSourceName.contains(keyword) || entry.url.contains(keyword)) &&
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
              decoration: InputDecoration(
                prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.textSecondary),
                hintText: '按名字或地址筛选',
                isDense: true,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none),
              ),
              onChanged: (value) => setState(() => _filter = value),
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
        tooltip: '导出',
        icon: const Icon(LucideIcons.share),
        onPressed: selected.isEmpty ? null : () => _export(repository, selected),
      ),
      IconButton(
        tooltip: '删除',
        icon: const Icon(LucideIcons.trash2),
        onPressed: selected.isEmpty ? null : () => _delete(repository, selected),
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
      final preview = previewImport(text, repository);
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
    content: preview.skipped.isEmpty
        ? null
        : SkippedList([for (final skipped in preview.skipped) '第 ${skipped.index + 1} 项：${skipped.reason}']),
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

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

const _typeLabels = {
  BookSourceType.audio: '音频',
  BookSourceType.image: '图片',
  BookSourceType.file: '文件',
  BookSourceType.video: '视频',
};
