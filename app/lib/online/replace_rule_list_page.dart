import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/icons.dart';
import '../ui/widgets.dart';
import 'import_text.dart';
import 'providers.dart';
import 'replace_rule_edit_page.dart';
import 'replace_rule_repository.dart';

/// 替换净化规则列表（replace-rules「导入替换规则」「规则列表」「导出替换规则」）：按执行顺序排列，逐条启用停用，点开编辑。
class ReplaceRuleListPage extends ConsumerStatefulWidget {
  const ReplaceRuleListPage({super.key});

  @override
  ConsumerState<ReplaceRuleListPage> createState() => _ReplaceRuleListPageState();
}

class _ReplaceRuleListPageState extends ConsumerState<ReplaceRuleListPage> {
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(replaceRuleRepositoryProvider);
    final entries = repository.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('替换净化规则'),
        actions: [
          IconButton(tooltip: '新建', icon: const Icon(LucideIcons.pencil), onPressed: () => _edit(null)),
          ImportMenuButton(onSelected: _import),
          IconButton(
            tooltip: '导出全部',
            icon: const Icon(LucideIcons.share),
            onPressed: entries.isEmpty ? null : () => _export(repository),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('还没有替换规则，点右上角导入或新建'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final rule = entry.rule;
                return ListTile(
                  title: Text(rule.name.isEmpty ? rule.pattern : rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Switch(value: entry.enabled, onChanged: (value) => repository.setEnabled(rule.id, value)),
                  onTap: () => _edit(entry),
                );
              },
            ),
    );
  }

  void _edit(ReplaceRuleEntry? entry) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReplaceRuleEditPage(editing: entry)));

  Future<void> _import(ImportFrom from) async {
    final repository = ref.read(replaceRuleRepositoryProvider);
    final engine = ref.read(sourceEngineProvider);
    try {
      final text = await readImportText(context, from, kind: '替换规则', hint: '单个规则对象或规则数组');
      if (text == null || !mounted) return;
      final ReplaceRuleImportPreview preview;
      try {
        preview = repository.preview(await engine.loadReplaceRules(text));
      } on FormatException catch (e) {
        throw ImportException('不是替换规则 JSON：${e.message}');
      }
      if (!mounted || !await _confirm(preview)) return;
      await repository.import(preview.rules);
      _snack('已导入 ${preview.rules.length} 条替换规则');
    } on ImportException catch (e) {
      if (mounted) await showImportError(context, e);
    }
  }

  Future<bool> _confirm(ReplaceRuleImportPreview preview) => showConfirmDialog(
    context,
    title: '导入替换规则',
    message: '新增 ${preview.added} 条，更新 ${preview.updated} 条，跳过 ${preview.skipped.length} 条',
    content: preview.skipped.isEmpty
        ? null
        : SkippedList([for (final skipped in preview.skipped) '第 ${skipped.index + 1} 项：${skipped.reason}']),
    confirmLabel: '导入',
    confirmEnabled: preview.rules.isNotEmpty,
  );

  Future<void> _export(ReplaceRuleRepository repository) async {
    await Clipboard.setData(ClipboardData(text: repository.export()));
    _snack('已复制 ${repository.entries.length} 条替换规则到剪贴板');
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
