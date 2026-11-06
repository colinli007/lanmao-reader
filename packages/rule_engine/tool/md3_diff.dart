// 和 MD3 的差分测试（md3-diff，change add-md3-diff）：同一批书源、同一个关键词，模拟器上的 MD3 跑「书源调试」，
// 我们的规则引擎同时照同样的流程跑（搜索第一本 → 详情 → 目录 → 第一章正文），逐项对比，写 JSON 报告和 Markdown 摘要。
//
// 准备：模拟器上装好 MD3，打开「Web 服务」，然后
//   adb forward tcp:1122 tcp:1122 && adb forward tcp:1123 tcp:1123
//   (cd ../quickjs_ng_ffi && ./tool/build_host.sh)
//   export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
//   dart run tool/md3_diff.dart --sources 书源.json --out 目录 [--md3-version 3.26.23] [--name 关键字] [--limit N]
//                                [--timeout 120] [--skip-import true] [--resume true] [--batch N]
//
// --resume：读入 --out 目录里已有的报告，跳过已经对比过的书源，接着往下跑（被中断后继续）。
// --batch：这次最多对比 N 个新书源就写报告退出，长时间的对比可以分几次在前台跑完。
//
// 只测文本类书源（app 只读文本）。MD3 的调试是全局的，一次只调试一个书源，所以按书源逐个来，两边同时开始。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import 'md3_diff/compare.dart';
import 'md3_diff/debug_result.dart';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final sourcesPath = options['sources'] ?? _usage();
  final outDir = Directory(options['out'] ?? _usage())..createSync(recursive: true);
  final http = options['md3'] ?? 'http://127.0.0.1:1122';
  final ws = options['ws'] ?? 'ws://127.0.0.1:1123';
  final version = options['md3-version'] ?? '3.26.23';
  final budget = Duration(seconds: int.parse(options['timeout'] ?? '120'));

  final text = File(sourcesPath).readAsStringSync();
  final seen = <String>{};
  var sources = [
    for (final source in loadBookSources(text).sources)
      if (source.bookSourceType == BookSourceType.text && seen.add(source.bookSourceUrl)) source,
  ];
  if (options['name'] case final name?) sources = [for (final s in sources) if (s.bookSourceName.contains(name)) s];
  if (options['limit'] case final limit?) sources = sources.take(int.parse(limit)).toList();

  if (options['skip-import'] != 'true') await _importToMd3(http, text);

  final host = RuleHost();
  final pool = WorkerPool(host.handle, size: 4, defaultTimeout: budget);
  final report = File('${outDir.path}/md3_diff.json');
  final previous = options['resume'] == 'true' && report.existsSync()
      ? jsonDecode(report.readAsStringSync()) as Map<String, Object?>
      : null;
  final started = previous == null ? DateTime.now() : DateTime.parse(previous['date']! as String);
  final diffs = [for (final json in (previous?['sources'] as List?) ?? const []) SourceDiff.fromJson(json as Map<String, Object?>)];
  final done = {for (final diff in diffs) diff.url};
  sources = [for (final s in sources) if (!done.contains(s.bookSourceUrl)) s];
  if (options['batch'] case final batch?) sources = sources.take(int.parse(batch)).toList();
  stderr.writeln('对比 ${sources.length} 个文本书源（已有 ${diffs.length} 个），MD3 $version');
  for (final (index, source) in sources.indexed) {
    final key = _keywordOf(source);
    final (ours, md3) = await (_runOurs(pool, source, key, budget), _runMd3(ws, source, key, budget)).wait;
    final diff = SourceDiff(name: source.bookSourceName, url: source.bookSourceUrl, key: key, ours: ours, md3: md3);
    diffs.add(diff);
    stderr.writeln('${index + 1}/${sources.length} ${diff.category.label}｜${source.bookSourceName}'
        '${diff.diffs.isEmpty ? '' : '｜${diff.diffs.map((d) => '${d.step.label}.${d.field}').join(',')}'}');
    if ((index + 1) % 10 == 0 || index + 1 == sources.length) _write(outDir, diffs, version, started);
  }
  if (sources.isEmpty) _write(outDir, diffs, version, started);
  pool.close();
  stdout.writeln(markdownSummary(diffs, md3Version: version, date: started));
  exit(0);
}

void _write(Directory dir, List<SourceDiff> diffs, String version, DateTime started) {
  File('${dir.path}/md3_diff.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'date': started.toIso8601String(),
      'md3Version': version,
      'sources': [for (final diff in diffs) diff.toJson()],
    }),
  );
  File('${dir.path}/md3_diff.md').writeAsStringSync(markdownSummary(diffs, md3Version: version, date: started));
}

/// 和书源校验相同（app 的 `checkKeywordOf`）：书源的 `ruleSearch.checkKeyWord` 可用时用它，否则用「我的」。
String _keywordOf(BookSource source) {
  final own = source.ruleSearch['checkKeyWord'];
  if (own == null || own.trim().isEmpty || const ['http', '::', '++', '--'].any(own.contains)) return '我的';
  return own;
}

Future<void> _importToMd3(String http, String text) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$http/saveBookSources'));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(text));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, Object?>;
    if (body['isSuccess'] != true) throw StateError('导入 MD3 失败：${body['errorMsg']}');
    stderr.writeln('已导入 MD3：${(body['data'] as List).length} 个书源');
  } finally {
    client.close();
  }
}

/// MD3 一侧：经 `/bookSourceDebug` 跑一次调试，收齐日志（连接关闭或超时为止）再解析。
Future<DebugResult> _runMd3(String ws, BookSource source, String key, Duration budget) async {
  final messages = <String>[];
  WebSocket? socket;
  try {
    socket = await WebSocket.connect('$ws/bookSourceDebug').timeout(const Duration(seconds: 10));
    socket.add(jsonEncode({'tag': source.bookSourceUrl, 'key': key}));
    await socket.forEach((message) => messages.add('$message')).timeout(budget);
  } on TimeoutException {
    // 没结束的一步由解析记为「没有结束」
  } catch (e) {
    messages.add('ConnectionError: $e');
  } finally {
    await socket?.close();
  }
  final canReName = source.ruleBookInfo['canReName']?.trim().isNotEmpty ?? false;
  return parseMd3Log(messages, canReName: canReName)..log.addAll([for (final m in messages) m.length > 300 ? '${m.substring(0, 300)}…' : m]);
}

/// 我们一侧：照 MD3 的 `Debug` 流程（add-md3-diff 设计 D2），整个流程最多 [budget]。
Future<DebugResult> _runOurs(WorkerPool pool, BookSource source, String key, Duration budget) async {
  final result = DebugResult();
  final deadline = DateTime.now().add(budget);
  Future<T> run<T>(T Function() task) {
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) throw TaskTimeoutException(budget);
    return pool.run(task, timeout: left);
  }

  Future<T?> step<T>(DebugStep name, Future<T> Function() body, void Function(Map<String, String> fields, T value) record) async {
    final step = result.step(name);
    try {
      final value = await body();
      step.ok = true;
      record(step.fields, value);
      return value;
    } catch (e) {
      step.error = _reason(e);
      return null;
    }
  }

  final first = await step(DebugStep.search, () async {
    final books = await run(searchTask(source, key));
    if (books.isEmpty) throw const _Failure('未获取到书籍');
    return (count: books.length, first: books.first);
  }, (fields, value) {
    fields
      ..['count'] = '${value.count}'
      ..['name'] = value.first.name
      ..['author'] = value.first.author
      ..['kind'] = value.first.kind ?? ''
      ..['wordCount'] = value.first.wordCount ?? ''
      ..['lastChapter'] = value.first.latestChapterTitle ?? ''
      ..['intro'] = value.first.intro ?? ''
      ..['coverUrl'] = value.first.coverUrl ?? ''
      ..['bookUrl'] = value.first.bookUrl;
  });
  if (first == null) return result;

  final book = await step(DebugStep.info, () => run(bookInfoTask(source, first.first.toBook())), (fields, book) {
    fields
      ..['name'] = book.name
      ..['author'] = book.author
      ..['kind'] = book.kind ?? ''
      ..['wordCount'] = book.wordCount ?? ''
      ..['lastChapter'] = book.latestChapterTitle ?? ''
      ..['intro'] = book.intro ?? ''
      ..['coverUrl'] = book.coverUrl ?? ''
      ..['tocUrl'] = book.tocUrl;
  });
  if (book == null) return result;
  if (source.bookSourceType == BookSourceType.file) {
    result.step(DebugStep.toc).skipped = true;
    result.step(DebugStep.content).skipped = true;
    return result;
  }

  final toc = await step(DebugStep.toc, () => run(chapterListTask(source, book)), (fields, toc) {
    fields['count'] = '${toc.chapters.length}';
  });
  if (toc == null) return result;
  // MD3：去掉「是卷且地址以标题开头」的章节，取第一章；下一章是第二章，没有时是第一章
  final chapters = [for (final c in toc.chapters) if (!(c.isVolume && c.url.startsWith(c.title))) c];
  if (chapters.isEmpty) {
    result.step(DebugStep.content).error = '没有正文章节';
    return result;
  }
  final chapter = chapters.first;
  final next = chapterAbsoluteUrl(chapters.length > 1 ? chapters[1] : chapter);
  await step(DebugStep.content, () => run(contentTask(source, toc.book, chapter, nextChapterUrl: next)), (fields, content) {
    fields
      ..['title'] = content.title
      ..['text'] = content.content;
  });
  return result;
}

final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

String _reason(Object error) {
  final text = switch (error) {
    RuleEngineException() => error.toString(),
    TaskTimeoutException() => '超时',
    HostCallException() => '网络：${error.message}',
    _ => '$error',
  };
  return text.split('\n').first;
}

Never _usage() {
  stderr.writeln('用法：dart run tool/md3_diff.dart --sources <书源.json> --out <目录> [--md3-version 版本] '
      '[--name 关键字] [--limit N] [--timeout 秒] [--skip-import true]');
  exit(64);
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) _usage();
    options[args[i].substring(2)] = args[i + 1];
  }
  return options;
}
