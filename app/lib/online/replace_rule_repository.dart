import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rule_engine/rule_engine.dart';

import '../storage/database.dart';

/// 一条替换净化规则和它的启用状态。启用状态以数据库的列为准，导出时写回 `isEnabled`（add-replace-rules 设计 D4）。
final class ReplaceRuleEntry {
  const ReplaceRuleEntry(this.rule, {required this.enabled});

  final ReplaceRule rule;
  final bool enabled;
}

/// 导入前的预览（replace-rules「导入替换规则」）：同一个 id 在内容里出现多次时，以最后一次为准。
final class ReplaceRuleImportPreview {
  const ReplaceRuleImportPreview({required this.rules, required this.added, required this.updated, required this.skipped});

  final List<ReplaceRule> rules;
  final int added;
  final int updated;
  final List<SkippedSource> skipped;
}

/// 替换净化规则，按执行顺序（`order`，再按 `id`）排列。启动时从数据库载入，之后的改动先写数据库再重新载入（设计 D7）。
final class ReplaceRuleRepository extends ChangeNotifier {
  ReplaceRuleRepository._(this._db, this._entries);

  final AppDatabase _db;
  List<ReplaceRuleEntry> _entries;
  late Map<int, ReplaceRuleEntry> _byId = _index(_entries);

  static Future<ReplaceRuleRepository> load(AppDatabase db) async => ReplaceRuleRepository._(db, await _read(db));

  List<ReplaceRuleEntry> get entries => _entries;

  /// 规则现在是否启用：净化时每条正则执行前读一次，别的章节刚停用的规则不再执行（设计 D5）。
  bool isEnabled(int id) => _byId[id]?.enabled ?? false;

  ReplaceRuleImportPreview preview(ReplaceRuleLoadResult result) {
    final byId = {for (final rule in result.rules) rule.id: rule};
    final updated = byId.keys.where(_byId.containsKey).length;
    return ReplaceRuleImportPreview(rules: [...byId.values], added: byId.length - updated, updated: updated, skipped: result.skipped);
  }

  /// 写入导入的规则，启用状态取规则里的 `isEnabled`。
  Future<void> import(List<ReplaceRule> rules) async {
    await _db.putReplaceRules([for (final rule in rules) _row(rule, enabled: rule.isEnabled)]);
    await _reload();
  }

  /// 新建（[editing] 为空）或编辑一条规则，[fields] 是表单里的字段。新建的规则启用，排在最后；
  /// 编辑时不在表单里的字段和启用状态不变（replace-rules「新建和编辑规则」）。
  Future<void> save(Map<String, Object?> fields, {ReplaceRuleEntry? editing}) async {
    final ReplaceRule rule;
    final bool enabled;
    if (editing != null) {
      rule = ReplaceRule({...editing.rule.json, ...fields});
      enabled = editing.enabled;
    } else {
      final maxId = _entries.map((entry) => entry.rule.id).fold(0, max);
      final maxOrder = _entries.map((entry) => entry.rule.order).fold<int?>(null, (a, b) => a == null ? b : max(a, b));
      rule = ReplaceRule({
        ...fields,
        'id': max(DateTime.now().millisecondsSinceEpoch, maxId + 1),
        'order': maxOrder == null ? 0 : maxOrder + 1,
        'isEnabled': true,
      });
      enabled = true;
    }
    await _db.putReplaceRules([_row(rule, enabled: enabled)]);
    await _reload();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _db.setReplaceRuleEnabled(id, enabled);
    await _reload();
  }

  /// 停用一条规则，返回这次是否从启用变成了停用：同一条规则在几章里同时超时，只提示一次（设计 D5）。
  Future<bool> disable(int id) async {
    if (!isEnabled(id)) return false;
    // 先改内存再写库：写库期间别的章节超时，读到的已经是停用
    _byId[id] = ReplaceRuleEntry(_byId[id]!.rule, enabled: false);
    await setEnabled(id, false);
    return true;
  }

  Future<void> delete(int id) async {
    await _db.deleteReplaceRule(id);
    await _reload();
  }

  /// 导出全部规则为 JSON 数组，`isEnabled` 为当前的启用状态（replace-rules「导出替换规则」）。
  String export() => const JsonEncoder.withIndent('  ').convert([
    for (final entry in _entries) {...entry.rule.json, 'isEnabled': entry.enabled},
  ]);

  Future<void> _reload() async {
    _entries = await _read(_db);
    _byId = _index(_entries);
    notifyListeners();
  }

  static Future<List<ReplaceRuleEntry>> _read(AppDatabase db) async {
    final entries = [
      for (final row in await db.allReplaceRules())
        ReplaceRuleEntry(ReplaceRule(jsonDecode(row.json) as Map<String, Object?>), enabled: row.enabled),
    ];
    return entries..sort((a, b) {
      final order = a.rule.order.compareTo(b.rule.order);
      return order != 0 ? order : a.rule.id.compareTo(b.rule.id);
    });
  }

  static ReplaceRuleRow _row(ReplaceRule rule, {required bool enabled}) =>
      ReplaceRuleRow(id: rule.id, json: jsonEncode(rule.json), enabled: enabled);

  static Map<int, ReplaceRuleEntry> _index(List<ReplaceRuleEntry> entries) => {for (final entry in entries) entry.rule.id: entry};
}
