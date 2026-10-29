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

  /// 分组：`bookSourceGroup` 按中英文逗号、分号拆开，去掉首尾空白，丢弃空的（source-management「书源列表」）。
  List<String> get groups => [
    for (final group in '${source.json['bookSourceGroup'] ?? ''}'.split(RegExp(r'[,;，；]')))
      if (group.trim() case final name when name.isNotEmpty) name,
  ];

  /// 参与搜索：启用、文本类、搜索地址不为空（book-search「发起搜索」）。
  bool get searchable => enabled && source.bookSourceType == BookSourceType.text && (source.searchUrl?.trim().isNotEmpty ?? false);
}

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
