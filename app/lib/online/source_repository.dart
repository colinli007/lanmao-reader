import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rule_engine/rule_engine.dart';

import '../storage/database.dart';

/// 一个已导入的书源。
final class SourceEntry {
  const SourceEntry(this.source, {required this.enabled});

  final BookSource source;
  final bool enabled;

  String get url => source.bookSourceUrl;

  List<String> get groups => splitGroups(source.json['bookSourceGroup']);

  /// 参与搜索：启用、文本类、搜索地址不为空（book-search「发起搜索」）。
  bool get searchable => enabled && source.bookSourceType == BookSourceType.text && (source.searchUrl?.trim().isNotEmpty ?? false);

  /// 出现在发现页：启用、文本类、没有关掉发现、发现地址不为空（explore「发现页的书源」，add-explore 设计 D2）。
  bool get explorable =>
      enabled && source.bookSourceType == BookSourceType.text && source.enabledExplore && (source.exploreUrl?.trim().isNotEmpty ?? false);
}

/// 分组：`bookSourceGroup` 按中英文逗号、分号拆开，去掉首尾空白，丢弃空的（source-management「书源列表」）。
List<String> splitGroups(Object? bookSourceGroup) => [
  for (final group in '${bookSourceGroup ?? ''}'.split(RegExp(r'[,;，；]')))
    if (group.trim() case final name when name.isNotEmpty) name,
];

/// 已导入的书源，按首次导入的顺序。启动时从数据库载入并解析一次，之后的改动先写数据库再更新内存。
final class SourceRepository extends ChangeNotifier {
  SourceRepository._(this._db, this._entries);

  final AppDatabase _db;
  List<SourceEntry> _entries;
  late Map<String, SourceEntry> _byUrl = _index(_entries);

  static Future<SourceRepository> load(AppDatabase db) async {
    final rows = await db.allSources();
    return SourceRepository._(db, [for (final row in rows) _parse(row)]);
  }

  List<SourceEntry> get entries => _entries;

  SourceEntry? operator [](String url) => _byUrl[url];

  /// 写入导入的书源，启用状态取原始 JSON 里的 `enabled`（只有 `false` 才停用）。
  Future<void> import(List<BookSource> sources) async {
    await _db.importSources([
      for (final source in sources) (url: source.bookSourceUrl, json: jsonEncode(source.json), enabled: source.json['enabled'] != false),
    ]);
    await _reload();
  }

  /// 用新的 JSON 替换一个已有的书源（书源地址不变），位置和启用状态不变；只替换内存里这一项，不整表重新载入
  /// （add-source-check 设计 D2）。书源已经被删除时不做任何事。
  Future<void> updateSource(Map<String, Object?> json) async {
    final text = jsonEncode(json);
    final source = loadBookSources(text).sources.single;
    final index = _entries.indexWhere((entry) => entry.url == source.bookSourceUrl);
    if (index < 0) return;
    await _db.updateSourceJson(source.bookSourceUrl, text);
    final entry = SourceEntry(source, enabled: _entries[index].enabled);
    _entries = [..._entries]..[index] = entry;
    _byUrl = {..._byUrl, entry.url: entry};
    notifyListeners();
  }

  Future<void> setEnabled(Set<String> urls, bool enabled) async {
    await _db.setSourcesEnabled(urls, enabled);
    await _reload();
  }

  Future<void> delete(Set<String> urls) async {
    await _db.deleteSources(urls);
    await _reload();
  }

  /// 导出为 JSON 数组：导入时的原始内容，只有 `enabled` 改为当前的启用状态（source-management「导出书源」）。
  String export(Set<String> urls) => const JsonEncoder.withIndent('  ').convert([
    for (final entry in _entries)
      if (urls.isEmpty || urls.contains(entry.url)) {...entry.source.json, 'enabled': entry.enabled},
  ]);

  Future<void> _reload() async {
    _entries = [for (final row in await _db.allSources()) _parse(row)];
    _byUrl = _index(_entries);
    notifyListeners();
  }

  static SourceEntry _parse(SourceRow row) => SourceEntry(loadBookSources(row.json).sources.single, enabled: row.enabled);

  static Map<String, SourceEntry> _index(List<SourceEntry> entries) => {for (final entry in entries) entry.url: entry};
}
