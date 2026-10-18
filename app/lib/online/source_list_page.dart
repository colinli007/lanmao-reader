import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

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

  /// 多选模式下选中的书源地址；为 null 时不在多选模式。
  Set<String>? _selected;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(sourceRepositoryProvider);
    final keyword = _filter.trim();
    final entries = [
      for (final entry in repository.entries)
        if (keyword.isEmpty || entry.source.bookSourceName.contains(keyword) || entry.url.contains(keyword)) entry,
    ];
    final selected = _selected;
    return Scaffold(
      appBar: selected == null ? _normalBar(repository) : _selectionBar(repository, selected, entries),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: '按名字或地址筛选', isDense: true),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: repository.entries.isEmpty
                ? const Center(child: Text('还没有书源，点右上角导入'))
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
      PopupMenuButton<_ImportFrom>(
        tooltip: '导入',
        icon: const Icon(Icons.add),
        onSelected: _import,
        itemBuilder: (_) => const [
          PopupMenuItem(value: _ImportFrom.file, child: Text('从文件导入')),
          PopupMenuItem(value: _ImportFrom.url, child: Text('从网址导入')),
          PopupMenuItem(value: _ImportFrom.text, child: Text('粘贴文本导入')),
        ],
      ),
      IconButton(
        tooltip: '书源日志',
        icon: const Icon(Icons.receipt_long_outlined),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourceLogPage())),
      ),
      IconButton(tooltip: '导出全部', icon: const Icon(Icons.ios_share), onPressed: () => _export(repository, const {})),
    ],
  );

  AppBar _selectionBar(SourceRepository repository, Set<String> selected, List<SourceEntry> visible) => AppBar(
    leading: IconButton(tooltip: '退出多选', icon: const Icon(Icons.close), onPressed: () => setState(() => _selected = null)),
    title: Text('已选 ${selected.length} 个'),
    actions: [
      IconButton(
        tooltip: '全选',
        icon: const Icon(Icons.select_all),
        onPressed: () => setState(() => _selected = {...selected, for (final entry in visible) entry.url}),
      ),
      IconButton(
        tooltip: '启用',
        icon: const Icon(Icons.check_circle_outline),
        onPressed: selected.isEmpty ? null : () => repository.setEnabled(selected, true),
      ),
      IconButton(
        tooltip: '停用',
        icon: const Icon(Icons.block),
        onPressed: selected.isEmpty ? null : () => repository.setEnabled(selected, false),
      ),
      IconButton(
        tooltip: '导出',
        icon: const Icon(Icons.ios_share),
        onPressed: selected.isEmpty ? null : () => _export(repository, selected),
      ),
      IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline),
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

  Future<void> _import(_ImportFrom from) async {
    final repository = ref.read(sourceRepositoryProvider);
    try {
      final text = switch (from) {
        _ImportFrom.file => await _pickFile(),
        _ImportFrom.url => switch (await _askUrl()) {
          final url? => await downloadSourceText(url),
          null => null,
        },
        _ImportFrom.text => await _askText(),
      };
      if (text == null || !mounted) return;
      final preview = previewImport(text, repository);
      if (await _confirm(preview) != true) return;
      await repository.import(preview.sources);
      _snack('已导入 ${preview.sources.length} 个书源');
    } on ImportException catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('无法导入'),
            content: Text(e.reason),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
          ),
        );
      }
    }
  }

  Future<String?> _pickFile() async {
    // Android 只按 MIME 过滤，下载来的书源文件常被识别成 application/octet-stream，不列上就选不了。
    // macOS 也会把 MIME 换成 UTType，octet-stream 在那里是 public.data（所有文件），所以只给 Android。
    final group = defaultTargetPlatform == TargetPlatform.android
        ? const XTypeGroup(label: '书源', mimeTypes: ['application/json', 'text/plain', 'application/octet-stream'])
        : const XTypeGroup(label: '书源', extensions: ['json', 'txt'], uniformTypeIdentifiers: ['public.json', 'public.plain-text']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    // 自己按 UTF-8 解码（和从网址导入一致）：Android 上的 XFile 是内存里的字节，它的 readAsString 不认编码，按 Latin-1 解出来中文是乱码
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  Future<String?> _askUrl() => _askInput(title: '从网址导入', hint: 'https://…', maxLines: 1);

  Future<String?> _askText() => _askInput(title: '粘贴书源 JSON', hint: '单个书源对象或书源数组', maxLines: 8);

  Future<String?> _askInput({required String title, required String hint, required int maxLines}) => showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(title: title, hint: hint, maxLines: maxLines),
  );

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
        FilledButton(
          onPressed: preview.sources.isEmpty ? null : () => Navigator.pop(context, true),
          child: const Text('导入'),
        ),
      ],
    ),
  );

  Future<void> _export(SourceRepository repository, Set<String> urls) async {
    final count = urls.isEmpty ? repository.entries.length : urls.length;
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

enum _ImportFrom { file, url, text }

/// 输入网址或文本的对话框，确定时把输入的文本作为结果返回。
class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.hint, required this.maxLines});

  final String title;
  final String hint;
  final int maxLines;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: widget.maxLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('确定')),
    ],
  );
}

const _typeLabels = {
  BookSourceType.audio: '音频',
  BookSourceType.image: '图片',
  BookSourceType.file: '文件',
  BookSourceType.video: '视频',
};
