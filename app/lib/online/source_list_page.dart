import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import '../ui/cinema.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart';
import 'import_text.dart';
import 'providers.dart';
import 'source_import.dart';
import 'source_repository.dart';

/// 书源管理（source-management，设计稿「书源管理 · 影院」）：导入、筛选、按分组看、启用与停用、多选批量操作、导出。
class SourceListPage extends ConsumerStatefulWidget {
  const SourceListPage({super.key});

  @override
  ConsumerState<SourceListPage> createState() => _SourceListPageState();
}

class _SourceListPageState extends ConsumerState<SourceListPage> {
  String _filter = '';

  /// 选中的分组；为 null 时是全部，空字符串是未分组。
  String? _group;

  /// 多选模式下选中的书源地址；为 null 时不在多选模式。
  Set<String>? _selected;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(sourceRepositoryProvider);
    final keyword = _filter.trim();
    final group = _group;
    final entries = [
      for (final entry in repository.entries)
        if ((keyword.isEmpty || entry.source.bookSourceName.contains(keyword) || entry.url.contains(keyword)) &&
            (group == null || (group.isEmpty ? entry.groups.isEmpty : entry.groups.contains(group))))
          entry,
    ];
    final groups = {for (final entry in repository.entries) ...entry.groups}.toList();
    final ungrouped = repository.entries.any((entry) => entry.groups.isEmpty);
    final selected = _selected;
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Night.bg,
        body: Stack(
          children: [
            const Positioned(
              left: -120,
              top: -200,
              width: 520,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0x2E8CC6A0), Color(0x008CC6A0)])),
              ),
            ),
            ListView(
              padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom + 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: selected == null ? _header() : _selectionHeader(repository, selected, entries),
                ),
                _Health(entries: repository.entries),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Night.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Night.line),
                    ),
                    child: Row(
                      spacing: 10,
                      children: [
                        const Icon(LucideIcons.search, size: 17, color: Night.text3),
                        Expanded(
                          child: TextField(
                            style: sans(14),
                            cursorColor: Night.amber,
                            decoration: InputDecoration(
                              hintText: '搜索书源名称或网址',
                              hintStyle: sans(14, color: Night.text3),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (value) => setState(() => _filter = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    spacing: 8,
                    children: [
                      CinemaChip(label: '全部', selected: group == null, onTap: () => setState(() => _group = null)),
                      for (final name in groups)
                        CinemaChip(label: name, selected: group == name, onTap: () => setState(() => _group = name)),
                      if (ungrouped && groups.isNotEmpty)
                        CinemaChip(label: '未分组', selected: group == '', onTap: () => setState(() => _group = '')),
                      CinemaChip(label: '失效', danger: true, onTap: () => showNotDeveloped(context, '书源校验')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: repository.entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            '还没有书源，点右上角导入',
                            textAlign: TextAlign.center,
                            style: sans(14, color: Night.text2),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Night.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Night.line),
                          ),
                          child: Column(
                            children: [
                              for (final (index, entry) in entries.indexed) _row(repository, entry, last: index == entries.length - 1),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(LucideIcons.info, size: 13, color: Night.text3),
                      ),
                      Expanded(
                        child: Text('本应用不内置、不分发任何书源。书源均由你自行导入，内容版权归原网站所有。', style: sans(11, color: Night.text3, height: 1.6)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      Expanded(
        child: Text('书源', style: sans(22, weight: FontWeight.w800)),
      ),
      GlassIconButton(icon: LucideIcons.shieldCheck, tooltip: '校验书源', onPressed: () => showNotDeveloped(context, '书源校验')),
      const SizedBox(width: 10),
      ImportMenuButton(
        onSelected: _import,
        child: const GlassIconButton(icon: LucideIcons.plus, tooltip: null, onPressed: null),
      ),
    ],
  );

  /// 多选时的顶栏：退出、已选数量、全选、启用、停用、导出、删除。
  Widget _selectionHeader(SourceRepository repository, Set<String> selected, List<SourceEntry> visible) {
    Widget action(String tooltip, IconData icon, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: onPressed == null ? Night.text3 : Night.text),
      onPressed: onPressed,
    );
    final empty = selected.isEmpty;
    return Row(
      children: [
        action('退出多选', LucideIcons.x, () => setState(() => _selected = null)),
        Expanded(
          child: Text('已选 ${selected.length} 个', style: sans(17, weight: FontWeight.w700)),
        ),
        action('全选', LucideIcons.listChecks, () => setState(() => _selected = {...selected, for (final entry in visible) entry.url})),
        action('启用', LucideIcons.circleCheck, empty ? null : () => repository.setEnabled(selected, true)),
        action('停用', LucideIcons.ban, empty ? null : () => repository.setEnabled(selected, false)),
        action('导出', LucideIcons.share, empty ? null : () => _export(repository, selected)),
        action('删除', LucideIcons.trash2, empty ? null : () => _delete(repository, selected)),
      ],
    );
  }

  /// 组件库「Source Row」：首字方块、名字、类型分组和域名、开关；停用的变暗。多选时首字方块换成勾选框。
  Widget _row(SourceRepository repository, SourceEntry entry, {required bool last}) {
    final source = entry.source;
    final name = source.bookSourceName.isEmpty ? source.bookSourceUrl : source.bookSourceName;
    final selected = _selected;
    final meta = [
      ?_typeLabels[source.bookSourceType],
      entry.groups.isEmpty ? '未分组' : entry.groups.join('、'),
      Uri.tryParse(entry.url)?.host.nullIfEmpty ?? entry.url,
    ].join(' · ');
    return InkWell(
      onTap: selected == null ? null : () => _toggleSelection(entry.url),
      onLongPress: () => setState(() => _selected = {...?selected, entry.url}),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Night.line)),
        ),
        child: Row(
          spacing: 12,
          children: [
            if (selected != null)
              SizedBox.square(
                dimension: 40,
                child: Checkbox(value: selected.contains(entry.url), onChanged: (_) => _toggleSelection(entry.url)),
              )
            else
              Opacity(
                opacity: entry.enabled ? 1 : 0.55,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Night.elevated, borderRadius: BorderRadius.circular(12)),
                  child: Text(name.characters.first, style: serif(17, color: Night.text2)),
                ),
              ),
            Expanded(
              child: Opacity(
                opacity: entry.enabled ? 1 : 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, weight: FontWeight.w600),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11, color: Night.text3),
                    ),
                  ],
                ),
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: entry.enabled,
                onChanged: (value) => repository.setEnabled({entry.url}, value),
              ),
            ),
          ],
        ),
      ),
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
      if (await _confirm(preview) != true) return;
      await repository.import(preview.sources);
      _snack('已导入 ${preview.sources.length} 个书源');
    } on ImportException catch (e) {
      if (mounted) await showImportError(context, e);
    }
  }

  Future<bool?> _confirm(ImportPreview preview) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入书源'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('新增 ${preview.added} 个，更新 ${preview.updated} 个，跳过 ${preview.skipped.length} 个'),
            for (final skipped in preview.skipped) Text('第 ${skipped.index + 1} 项：${skipped.reason}'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: preview.sources.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('导入')),
      ],
    ),
  );

  Future<void> _export(SourceRepository repository, Set<String> urls) async {
    final count = urls.length;
    await Clipboard.setData(ClipboardData(text: repository.export(urls)));
    _snack('已复制 $count 个书源到剪贴板');
  }

  Future<void> _delete(SourceRepository repository, Set<String> urls) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${urls.length} 个书源？'),
        content: const Text('书架上来自这些书源的书会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.delete(urls);
    setState(() => _selected = null);
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

const _typeLabels = {BookSourceType.audio: '音频', BookSourceType.image: '图片', BookSourceType.file: '文件', BookSourceType.video: '视频'};

/// 启用数的大数字和启用比例条。可用、响应慢、失效要靠书源校验，还没做，点了只提示。
class _Health extends StatelessWidget {
  const _Health({required this.entries});

  final List<SourceEntry> entries;

  @override
  Widget build(BuildContext context) {
    final enabled = entries.where((entry) => entry.enabled).length;
    final disabled = entries.length - enabled;
    Widget legend(Color color, String label) => Row(
      spacing: 6,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(label, style: sans(12, color: Night.text2)),
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showNotDeveloped(context, '书源校验'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 14,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 10,
              children: [
                Text('$enabled', style: serif(56, height: 1)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text('/ ${entries.length} 个书源已启用', style: sans(13, color: Night.text2)),
                      Text('还没有校验过', style: sans(11, color: Night.text3)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 3,
                children: [
                  if (enabled > 0)
                    Expanded(
                      flex: enabled,
                      child: _Segment(color: Night.ok),
                    ),
                  if (disabled > 0)
                    Expanded(
                      flex: disabled,
                      child: _Segment(color: Night.glass),
                    ),
                  if (entries.isEmpty) const Expanded(child: _Segment(color: Night.glass)),
                ],
              ),
            ),
            Row(spacing: 18, children: [legend(Night.ok, '已启用 $enabled'), legend(Night.text3, '已停用 $disabled')]),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
