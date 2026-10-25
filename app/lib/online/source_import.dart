import 'package:rule_engine/rule_engine.dart';

import 'import_text.dart';
import 'source_repository.dart';

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
