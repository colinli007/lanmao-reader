import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';

import 'source_repository.dart';

/// 导入失败的原因（内容不是书源 JSON、下载失败），给用户看。
final class ImportException implements Exception {
  const ImportException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 写入前的预览（source-management「导入书源」）：同一个书源地址在内容里出现多次时，以最后一次为准。
final class ImportPreview {
  const ImportPreview({required this.sources, required this.added, required this.updated, required this.skipped});

  final List<BookSource> sources;
  final int added;
  final int updated;
  final List<SkippedSource> skipped;
}

ImportPreview previewImport(String text, SourceRepository repository) {
  final BookSourceLoadResult result;
  try {
    result = loadBookSources(text);
  } on FormatException catch (e) {
    throw ImportException('不是书源 JSON：${e.message}');
  }
  final byUrl = {for (final source in result.sources) source.bookSourceUrl: source};
  final updated = byUrl.keys.where((url) => repository[url] != null).length;
  return ImportPreview(sources: [...byUrl.values], added: byUrl.length - updated, updated: updated, skipped: result.skipped);
}

/// 下载网址上的书源文件：主 isolate 上直接请求，不走引擎、不带 Cookie；按 UTF-8 解码（书源 JSON 都是 UTF-8）。
Future<String> downloadSourceText(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) throw const ImportException('不是有效的网址');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 30));
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk)).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) throw ImportException('下载失败：HTTP ${response.statusCode}');
    return utf8.decode(bytes, allowMalformed: true);
  } on ImportException {
    rethrow;
  } on Exception catch (e) {
    throw ImportException('下载失败：$e');
  } finally {
    client.close(force: true);
  }
}
