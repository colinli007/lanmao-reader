import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import 'batch.dart';
import 'errors.dart';
import 'providers.dart';
import 'source_repository.dart';

/// 校验失败的种类，[group] 是标到书源上的失效分组，名字和 Legado 相同（source-check「标记结果」）。
enum CheckInvalid {
  noSearchUrl('搜索链接规则为空'),
  searchEmpty('搜索失效'),
  tocEmpty('搜索目录失效'),
  contentEmpty('搜索正文失效'),
  timeout('校验超时'),
  js('js失效'),
  site('网站失效');

  const CheckInvalid(this.group);

  final String group;
}

/// 一个书源校验失败的种类和写进注释的原因。
typedef CheckFailure = ({CheckInvalid kind, String reason});

/// 校验标上的分组，重新校验时先去掉：Legado 的失效分组（名字里带「失效」或者是「校验超时」，`getInvalidGroupNames`），
/// 以及「搜索链接规则为空」（Legado 在书源有搜索地址时单独去掉它）。
bool isCheckGroup(String group) => group.contains('失效') || CheckInvalid.values.any((kind) => kind.group == group);

const String _errorPrefix = '// Error: ';

/// 去掉书源 JSON 上次校验留下的失效分组和错误注释，失败时再标上这次的（add-source-check 设计 D2）。
/// 只在有标记要去掉或要加上时改写对应字段；改写后为空时去掉这个字段（空和没有一样，这样标记去掉后能还原成导入时的样子）。
Map<String, Object?> markCheckResult(Map<String, Object?> json, CheckFailure? failure) {
  final result = {...json};
  void put(String key, String value) => value.isEmpty ? result.remove(key) : result[key] = value;

  final groups = splitGroups(json['bookSourceGroup']);
  final kept = [for (final group in groups) if (!isCheckGroup(group)) group];
  if (failure != null && !kept.contains(failure.kind.group)) kept.add(failure.kind.group);
  if (failure != null || kept.length != groups.length) put('bookSourceGroup', kept.join(','));

  final comment = '${json['bookSourceComment'] ?? ''}';
  final paragraphs = comment.isEmpty ? <String>[] : comment.split('\n\n');
  final notes = [for (final paragraph in paragraphs) if (!paragraph.startsWith(_errorPrefix)) paragraph];
  if (failure != null) notes.insert(0, '$_errorPrefix${failure.reason}');
  if (failure != null || notes.length != paragraphs.length) put('bookSourceComment', notes.join('\n\n'));
  return result;
}

/// 书源用来校验的关键词：`ruleSearch.checkKeyWord` 可用时用它，否则用 [fallback]（Legado `getCheckKeyword`）。
String checkKeywordOf(BookSource source, String fallback) {
  final own = source.ruleSearch['checkKeyWord'];
  if (own == null || own.trim().isEmpty || const ['http', '::', '++', '--'].any(own.contains)) return fallback;
  return own;
}

final class SourceCheckState {
  const SourceCheckState({this.done = 0, this.total = 0, this.invalid = 0, this.running = false});

  /// 已完成的书源数和这次校验的书源总数。
  final int done;
  final int total;

  /// 这次校验里被标上名字带「失效」的分组的书源数：筛选「失效」能看到的那些，Legado 据此自动筛选。
  final int invalid;
  final bool running;

  SourceCheckState copyWith({int? done, int? invalid, bool? running}) =>
      SourceCheckState(done: done ?? this.done, total: total, invalid: invalid ?? this.invalid, running: running ?? this.running);
}

/// 书源校验（source-check），做法照 Legado 的 `CheckSourceService`：同时最多 [concurrency] 个书源，
/// 每个书源最多 [timeout]，完成一个写回一个。生命周期跟 app，离开书源页面不中断（设计 D4）。
final class SourceCheckController extends Notifier<SourceCheckState> {
  SourceCheckController({this.timeout = const Duration(seconds: 180)});

  static const int concurrency = 16;

  final Duration timeout;
  Batch? _batch;

  @override
  SourceCheckState build() => const SourceCheckState();

  /// 开始校验 [sources]；已经在校验时不开始，返回 false。
  bool start(List<BookSource> sources, String keyword) {
    if (state.running) return false;
    final batch = _batch = Batch();
    final queue = Queue.of(sources);
    state = SourceCheckState(total: sources.length, running: sources.isNotEmpty);
    for (var i = 0; i < min(concurrency, sources.length); i++) {
      unawaited(_work(batch, queue, keyword));
    }
    return true;
  }

  /// 停止：进行中的书源被取消、不写结果，没开始的不再开始，已完成的保留。
  void stop() {
    if (!state.running) return;
    _batch?.stop();
    state = state.copyWith(running: false);
  }

  Future<void> _work(Batch batch, Queue<BookSource> queue, String keyword) async {
    while (queue.isNotEmpty && !batch.isStopped) {
      final source = queue.removeFirst();
      final failure = await _check(source, checkKeywordOf(source, keyword), batch);
      if (batch.isStopped) return;
      await _write(source.bookSourceUrl, failure);
      final done = state.done + 1;
      final invalid = failure != null && failure.kind.group.contains('失效');
      state = state.copyWith(done: done, invalid: state.invalid + (invalid ? 1 : 0), running: done < state.total);
    }
  }

  Future<CheckFailure?> _check(BookSource source, String keyword, Batch batch) async {
    try {
      return await _steps(source, keyword, batch).timeout(
        timeout,
        onTimeout: () => (kind: CheckInvalid.timeout, reason: '超时：超过 ${timeout.inSeconds} 秒'),
      );
    } catch (error) {
      return _classify(error);
    }
  }

  /// 搜索 → 第一本书的详情 → 目录 → 第一个不是卷名的章节的正文；文件类书源到详情为止（设计 D1）。
  Future<CheckFailure?> _steps(BookSource source, String keyword, Batch batch) async {
    if (source.searchUrl?.trim().isEmpty ?? true) return _marked(CheckInvalid.noSearchUrl);
    final engine = ref.read(sourceEngineProvider);
    final books = await engine.search(source, keyword, batch);
    if (books.isEmpty) return _marked(CheckInvalid.searchEmpty);
    final book = await engine.bookInfo(source, books.first.toBook(), batch: batch);
    if (source.bookSourceType == BookSourceType.file) return null;
    final toc = await engine.chapterList(source, book, batch: batch);
    final chapters = [for (final chapter in toc.chapters) if (!chapter.isVolume) chapter];
    // 目录里只有卷名：没有能读的章节，和目录为空一样
    if (chapters.isEmpty) return _marked(CheckInvalid.tocEmpty);
    final next = chapters.length > 1 ? chapterAbsoluteUrl(chapters[1]) : null;
    await engine.content(source, toc.book, chapters.first, nextChapterUrl: next, batch: batch);
    return null;
  }

  /// Legado 的 `NoStackTraceException` 路径：注释里写的就是分组名。
  static CheckFailure _marked(CheckInvalid kind) => (kind: kind, reason: kind.group);

  /// 失败归类（设计 D3）：目录、正文为空各有分组，书源 JS 的问题是「js失效」，其余是「网站失效」。
  static CheckFailure _classify(Object error) => switch (error) {
    RuleException(message: RuleException.tocEmpty) => _marked(CheckInvalid.tocEmpty),
    RuleException(message: RuleException.contentEmpty) => _marked(CheckInvalid.contentEmpty),
    JsEvalException() || NeedsJsException() || UnsupportedHostApiException() => (kind: CheckInvalid.js, reason: describeError(error)),
    _ => (kind: CheckInvalid.site, reason: describeError(error)),
  };

  /// 写回当前的书源（校验期间它可能被更新过）；书源已被删除、或者没有要改的标记时不写。
  Future<void> _write(String url, CheckFailure? failure) async {
    final repository = ref.read(sourceRepositoryProvider);
    final json = repository[url]?.source.json;
    if (json == null) return;
    final marked = markCheckResult(json, failure);
    if (!mapEquals(marked, json)) await repository.updateSource(marked);
  }
}

final sourceCheckProvider = NotifierProvider<SourceCheckController, SourceCheckState>(SourceCheckController.new);
