// 联网冒烟：对一批书源跑完整的四条链路（搜索 → 详情 → 目录 → 第一章正文），统计各链路的成功数和失败原因。
//
//   (cd ../quickjs_ng_ffi && ./tool/build_host.sh)
//   export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
//   dart run tool/smoke.dart --sources 书源.json --key 斗罗大陆 [--only a.json] [--name 关键字] [--limit 20]
//                            [--shuffle 种子] [--concurrency 4] [--json 结果.json] [--record 目录]
//
// --only：source-check 输出的 JSON（`--list --level a --json`），只测其中列出的书源。
// --record：把每个书源的全部请求和响应存成固定样例（test/fixtures/recorded/ 下的格式），用于回放测试。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/http_frame.dart';
import 'package:rule_engine/src/request/response_decoder.dart';
import 'package:rule_engine/src/worker/worker_environment.dart';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final sourcesPath = options['sources'] ?? _usage();
  final key = options['key'] ?? _usage();
  var sources = loadBookSources(File(sourcesPath).readAsStringSync()).sources;
  if (options['only'] case final only?) {
    final listed = jsonDecode(File(only).readAsStringSync()) as Map<String, Object?>;
    final urls = {for (final s in (listed['sources'] as List).cast<Map<String, Object?>>()) s['url']};
    sources = sources.where((s) => urls.contains(s.bookSourceUrl)).toList();
  }
  if (options['name'] case final name?) {
    sources = sources.where((s) => s.bookSourceName.contains(name) || s.bookSourceUrl.contains(name)).toList();
  }
  // 同一个地址只测一次
  final seen = <String>{};
  sources = sources.where((s) => seen.add(s.bookSourceUrl)).toList();
  if (options['shuffle'] case final seed?) sources.shuffle(Random(int.parse(seed)));
  if (options['limit'] case final limit?) sources = sources.take(int.parse(limit)).toList();
  final concurrency = int.parse(options['concurrency'] ?? '4');
  final recordDir = options['record'];

  // 书源 JS 的日志按书源地址收集，每个书源最多留 20 条，写进结果便于排查
  final logs = <String, List<String>>{};
  final host = RuleHost(onLog: (log) {
    final list = logs.putIfAbsent(log.sourceUrl, () => []);
    if (list.length < 20) list.add('${log.field ?? ''} ${log.message}'.trim());
  });
  final recorder = _Recorder(host, recording: recordDir != null);
  final pool = WorkerPool(recorder.handle, size: concurrency, defaultTimeout: const Duration(seconds: 90));
  stderr.writeln('测试 ${sources.length} 个书源，搜索词「$key」');

  final reports = <_Report>[];
  var next = 0;
  Future<void> worker() async {
    while (next < sources.length) {
      final source = sources[next++];
      final report = await _run(pool, source, key);
      report.logs.addAll(logs.remove(source.bookSourceUrl) ?? const []);
      reports.add(report);
      stderr.writeln('${reports.length}/${sources.length} ${report.line}');
      if (recordDir != null) {
        final file = File('$recordDir/${_fileName(source)}.json');
        file.writeAsStringSync(
          const JsonEncoder.withIndent(' ').convert({
            'recordedAt': DateTime.now().toIso8601String(),
            'key': key,
            'source': source.toJson(),
            'records': recorder.take(source.bookSourceUrl),
            'result': report.result,
            'failures': report.failures,
          }),
        );
      }
    }
  }

  // 录制时一个书源一个书源地跑，请求不会混在一起
  await Future.wait([for (var i = 0; i < (recordDir == null ? concurrency : 1); i++) worker()]);
  pool.close();

  final summary = _summary(reports);
  stdout.writeln(summary);
  if (options['json'] case final path?) {
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'date': DateTime.now().toIso8601String(),
        'key': key,
        'sources': [for (final r in reports) r.toJson()],
      }),
    );
  }
  exit(0);
}

Never _usage() {
  stderr.writeln('用法：dart run tool/smoke.dart --sources <书源.json> --key <搜索词> [--only a.json] [--name 关键字] '
      '[--shuffle 种子] [--limit N] [--concurrency N] [--json 结果.json] [--record 目录]');
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

/// 用整个书源地址生成文件名：同一主机下可能有多个书源。
String _fileName(BookSource source) => source.bookSourceUrl
    .replaceFirst(RegExp(r'^https?://'), '')
    .replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '_')
    .replaceAll(RegExp(r'_+$'), '');

const List<String> _stages = ['搜索', '详情', '目录', '正文'];

final class _Report {
  _Report(this.source);

  final BookSource source;
  final Map<String, String> failures = {};
  final List<String> passed = [];
  final Map<String, Object?> result = {};

  /// 书源 JS 写的日志（java.log、toast、请求头 JS 的错误）。
  final List<String> logs = [];

  bool get completed => passed.length == _stages.length;

  String get line {
    final stage = failures.keys.firstOrNull;
    return '${source.bookSourceName}（${source.bookSourceUrl}）：'
        '${completed ? '全部通过' : '$stage失败：${failures[stage]}'}';
  }

  Map<String, Object?> toJson() => {
    'name': source.bookSourceName,
    'url': source.bookSourceUrl,
    'passed': passed,
    'failures': failures,
    'result': result,
    if (logs.isNotEmpty) 'logs': logs,
  };
}

Future<_Report> _run(WorkerPool pool, BookSource source, String key) async {
  final report = _Report(source);
  Future<T?> stage<T>(String name, Future<T> Function() body) async {
    try {
      final value = await body();
      report.passed.add(name);
      return value;
    } catch (e) {
      report.failures[name] = _reason(e);
      return null;
    }
  }

  final books = await stage('搜索', () async {
    final books = await pool.run(searchTask(source, key));
    if (books.isEmpty) throw const _NoResult('搜索无结果');
    return books;
  });
  if (books == null) return report;
  final picked = books.firstWhere((b) => b.name.contains(key), orElse: () => books.first);
  report.result['searchCount'] = books.length;

  final book = await stage('详情', () => pool.run(bookInfoTask(source, picked.toBook())));
  if (book == null) return report;
  report.result
    ..['name'] = book.name
    ..['author'] = book.author
    ..['bookUrl'] = book.bookUrl
    ..['tocUrl'] = book.tocUrl;

  final toc = await stage('目录', () => pool.run(chapterListTask(source, book)));
  if (toc == null) return report;
  final chapters = toc.chapters;
  report.result
    ..['chapterCount'] = chapters.length
    ..['firstChapter'] = chapters.first.title
    ..['lastChapter'] = chapters.last.title;

  final first = chapters.firstWhere((c) => !c.isVolume, orElse: () => chapters.first);
  final index = chapters.indexOf(first);
  final nextUrl = index + 1 < chapters.length ? chapterAbsoluteUrl(chapters[index + 1]) : null;
  final content = await stage('正文', () => pool.run(contentTask(source, toc.book, first, nextChapterUrl: nextUrl)));
  if (content == null) return report;
  report.result
    ..['chapter'] = first.title
    ..['contentLength'] = content.content.length
    ..['contentHead'] = content.content.length > 60 ? content.content.substring(0, 60) : content.content;
  return report;
}

final class _NoResult implements Exception {
  const _NoResult(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 失败原因归类：错误类型加消息的开头。
String _reason(Object error) {
  final text = switch (error) {
    RuleEngineException() => error.toString(),
    TaskTimeoutException() => '任务超时',
    HostCallException() => '网络：${error.message}',
    _ => '$error',
  };
  final firstLine = text.split('\n').first;
  return firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine;
}

String _summary(List<_Report> reports) {
  final out = StringBuffer('\n## 冒烟结果（${reports.length} 个书源）\n\n| 链路 | 成功 | 失败 |\n|---|---|---|\n');
  var reached = reports.length;
  for (final stage in _stages) {
    final ok = reports.where((r) => r.passed.contains(stage)).length;
    out.writeln('| $stage | $ok | ${reached - ok} |');
    reached = ok;
  }
  final reasons = <String, int>{};
  for (final report in reports) {
    for (final MapEntry(key: stage, value: reason) in report.failures.entries) {
      reasons.update('$stage｜${_category(reason)}', (n) => n + 1, ifAbsent: () => 1);
    }
  }
  out.writeln('\n失败原因：\n');
  for (final entry in reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    out.writeln('- ${entry.key}：${entry.value}');
  }
  return out.toString();
}

/// 把消息里的地址、书源名去掉，便于归类。
String _category(String reason) {
  if (reason.startsWith('网络：')) {
    if (reason.contains('Timeout') || reason.contains('超时')) return '网络超时';
    if (reason.contains('Failed host lookup') || reason.contains('nodename')) return '域名解析失败';
    if (reason.contains('Connection refused')) return '连接被拒绝';
    if (reason.contains('Handshake') || reason.contains('TLS')) return 'TLS 握手失败';
    return '网络错误';
  }
  if (reason.startsWith('需要 WebView')) return '需要 WebView';
  if (reason.startsWith('不支持的 JS 用法')) return '不支持的 JS 用法';
  // 不支持的宿主 API 按 API 名归类，JS 错误按错误类型归类
  final api = RegExp(r'^不支持的宿主 API：(\S+?)（').firstMatch(reason);
  if (api != null) return '不支持的宿主 API：${api.group(1)}';
  final jsError = RegExp(r'^JS 错误：(\w*Error)').firstMatch(reason);
  if (jsError != null) return 'JS 错误：${jsError.group(1)}';
  return reason.replaceAll(RegExp(r'（.*）$'), '');
}

/// 包一层宿主处理：记下每个请求和响应，按书源地址分组。
final class _Recorder {
  _Recorder(this._host, {required this.recording});

  final RuleHost _host;
  final bool recording;
  final Map<String, List<Map<String, Object?>>> _records = {};

  Future<Object?> handle(HostCall call) async {
    final reply = await _host.handle(call);
    // 只录网络请求，书源级状态和日志不录（回放环境自己有一份内存状态）
    if (!recording || (call.op != RuleHostOps.http && call.op != RuleHostOps.httpBatch)) return reply;
    final requests = switch (call.payload) {
      final List<Object?> list => [for (final json in list) HttpRequest.fromJson((json as Map).cast())],
      final Map<Object?, Object?> json => [HttpRequest.fromJson(json.cast())],
      _ => const <HttpRequest>[],
    };
    final results = decodeHttpResults(reply! as Uint8List);
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      final result = results[i];
      (_records[request.sourceUrl] ??= []).add({
        'method': request.method,
        'url': request.url,
        'body': request.body,
        'status': result.statusCode,
        'finalUrl': result.url,
        'redirected': result.redirected,
        'headers': result.headers,
        if (result.setCookies.isNotEmpty) 'setCookies': result.setCookies,
        'response': base64Encode(result.body),
        // 方便人工核对：解码后的前 200 个字符
        'preview': _preview(decodeResponseBody(result)),
      });
    }
    return reply;
  }

  List<Map<String, Object?>> take(String sourceUrl) => _records.remove(sourceUrl) ?? [];

  static String _preview(String text) => text.length > 200 ? text.substring(0, 200) : text;
}
