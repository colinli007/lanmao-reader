import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'providers.dart';
import 'replace_rule_repository.dart';

/// 新建（[editing] 为空）或编辑一条替换净化规则（replace-rules「新建和编辑规则」）。
/// 保存前在 worker 里校验正则（add-replace-rules 设计 D3）；编辑时可以删除。
class ReplaceRuleEditPage extends ConsumerStatefulWidget {
  const ReplaceRuleEditPage({super.key, this.editing});

  final ReplaceRuleEntry? editing;

  @override
  ConsumerState<ReplaceRuleEditPage> createState() => _ReplaceRuleEditPageState();
}

class _ReplaceRuleEditPageState extends ConsumerState<ReplaceRuleEditPage> {
  late final _rule = widget.editing?.rule;
  late final _name = TextEditingController(text: _rule?.name);
  late final _pattern = TextEditingController(text: _rule?.pattern);
  late final _replacement = TextEditingController(text: _rule?.replacement);
  late final _scope = TextEditingController(text: _rule?.scope);
  late final _excludeScope = TextEditingController(text: _rule?.excludeScope);
  late bool _isRegex = _rule?.isRegex ?? true;
  late bool _scopeContent = _rule?.scopeContent ?? true;
  late bool _scopeTitle = _rule?.scopeTitle ?? false;

  /// 不能保存的原因，显示在替换规则输入框下面。
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _pattern, _replacement, _scope, _excludeScope]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.editing == null ? '新建替换规则' : '编辑替换规则'),
      actions: [
        if (widget.editing != null) IconButton(tooltip: '删除', icon: const Icon(LucideIcons.trash2), onPressed: _delete),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    ),
    // 输入框是浅灰底、无边框（设计 D2），相邻的要隔开；开关和输入框左右对齐
    body: ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.item, AppSpacing.page, AppSpacing.section),
      children: [
        Column(
          spacing: AppSpacing.item,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: '名称')),
            TextField(
              controller: _pattern,
              maxLines: null,
              decoration: InputDecoration(labelText: '替换规则', errorText: _error),
            ),
            TextField(controller: _replacement, maxLines: null, decoration: const InputDecoration(labelText: '替换为')),
            TextField(controller: _scope, decoration: const InputDecoration(labelText: '作用范围', helperText: '书名或书源地址，为空时作用于所有书')),
            TextField(controller: _excludeScope, decoration: const InputDecoration(labelText: '排除范围', helperText: '书名或书源地址')),
          ],
        ),
        const SizedBox(height: AppSpacing.item),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用正则'),
          value: _isRegex,
          onChanged: (value) => setState(() => _isRegex = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('作用于正文'),
          value: _scopeContent,
          onChanged: (value) => setState(() => _scopeContent = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('作用于章节名'),
          value: _scopeTitle,
          onChanged: (value) => setState(() => _scopeTitle = value),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final repository = ref.read(replaceRuleRepositoryProvider);
    final pattern = _pattern.text;
    final error = await ref.read(sourceEngineProvider).replaceRuleError(pattern, isRegex: _isRegex);
    if (!mounted) return;
    if (error != null) return setState(() => _error = error);
    await repository.save({
      'name': _name.text,
      'pattern': pattern,
      'replacement': _replacement.text,
      'isRegex': _isRegex,
      'scope': _scope.text,
      'excludeScope': _excludeScope.text,
      'scopeContent': _scopeContent,
      'scopeTitle': _scopeTitle,
    }, editing: widget.editing);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(context, title: '删除这条替换规则？', confirmLabel: '删除', danger: true);
    if (!confirmed || !mounted) return;
    await ref.read(replaceRuleRepositoryProvider).delete(widget.editing!.rule.id);
    if (mounted) Navigator.of(context).pop();
  }
}
