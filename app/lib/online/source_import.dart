import 'package:rule_engine/rule_engine.dart';

import 'import_text.dart';
import 'source_repository.dart';

/// 写入前的预览（source-management「导入书源」）：同一个书源地址在内容里出现多次时，以最后一次为准。
final class ImportPreview {
  const ImportPreview({required this.sources, required this.added, required this.updated, required this.skipped});

  final List<BookSource> sources;
  final int added;
  final int updated;

  /// 被跳过的条目，每项一行：位置（来自网址列表时带网址）和原因。
  final List<String> skipped;
}

/// 解析要导入的内容。内容是网址列表时下载其中每个网址再合并（improve-source-import 设计 D3）；
/// 内容是书源 JSON 但一个可用书源都没有时，抛出带原因的 [ImportException]（设计 D1）。
Future<ImportPreview> previewImport(String text, SourceRepository repository) async {
  final result = _loadSources(text);
  final sources = [...result.sources];
  final skipped = [for (final item in result.skipped) _skippedLine(item)];
  for (final file in await Future.wait(result.sourceUrls.map(_loadUrl))) {
    sources.addAll(file.sources);
    skipped.addAll(file.skipped);
  }
  final byUrl = {for (final source in sources) source.bookSourceUrl: source};
  final updated = byUrl.keys.where((url) => repository[url] != null).length;
  return ImportPreview(sources: [...byUrl.values], added: byUrl.length - updated, updated: updated, skipped: skipped);
}

/// 网址列表里一个网址的书源和跳过行（带网址）；下载失败、不是书源时只有一行原因。
/// 只展开一层，下载到的又是网址列表时算没有书源。
Future<({List<BookSource> sources, List<String> skipped})> _loadUrl(String url) async {
  try {
    final result = _loadSources(await downloadText(url));
    if (result.sourceUrls.isNotEmpty) throw const ImportException(_noSources);
    return (sources: result.sources, skipped: [for (final item in result.skipped) '$url ${_skippedLine(item)}']);
  } on ImportException catch (e) {
    return (sources: const <BookSource>[], skipped: ['$url：${e.reason}']);
  }
}

/// 载入书源 JSON；内容不是网址列表、又一个可用书源都没有时，按内容说明原因。
BookSourceLoadResult _loadSources(String text) {
  final BookSourceLoadResult result;
  try {
    result = loadBookSources(text);
  } on FormatException {
    throw ImportException(_notSource(text));
  }
  if (result.sources.isNotEmpty || result.sourceUrls.isNotEmpty) return result;
  if (result.skipped.isEmpty) throw const ImportException(_noSources);
  if (result.skipped.every((item) => item.reason == rssSourceSkipReason)) {
    throw const ImportException('这是订阅源，不是书源，暂不支持订阅源');
  }
  throw ImportException(_notSource(text));
}

const String _noSources = '内容里没有书源';

const int _headLength = 100;

/// 「不是书源」并附上内容开头，让用户看到实际拿到的是什么：按码点截取，连续空白合并成一个空格。
String _notSource(String text) {
  final runes = text.trim().replaceAll(RegExp(r'\s+'), ' ').runes;
  final head = String.fromCharCodes(runes.take(_headLength));
  return '不是书源。内容开头：$head${runes.length > _headLength ? '…' : ''}';
}

String _skippedLine(SkippedSource item) => '第 ${item.index + 1} 项：${item.reason}';
