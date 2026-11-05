import 'dart:async';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

import '../library/content_source.dart';
import '../storage/database.dart';
import 'batch.dart';
import 'book_mapping.dart';
import 'errors.dart';
import 'replace_rule_repository.dart';
import 'source_engine.dart';
import 'source_repository.dart';

/// 书架和阅读器的在线内容来源：用书源执行目录、正文链路，按替换净化规则处理正文。停用的书源照样能用（只影响搜索）。
final class OnlineContentSource implements BookContentSource {
  OnlineContentSource(this._engine, this._sources, this._rules);

  final SourceEngine _engine;
  final SourceRepository _sources;
  final ReplaceRuleRepository _rules;

  @override
  bool hasSource(String origin) => _sources[origin] != null;

  @override
  Future<ChapterText> loadContent(ShelfBook book, TocChapter chapter, {TocChapter? next}) async {
    final entry = _sources[book.origin];
    if (entry == null) throw const ContentLoadException.sourceMissing();
    try {
      final content = await _engine.content(
        entry.source,
        engineBookOf(book),
        engineChapterOf(chapter),
        nextChapterUrl: next == null ? null : chapterAbsoluteUrl(engineChapterOf(next)),
      );
      return (title: content.title, content: content.content);
    } catch (e) {
      throw ContentLoadException(describeError(e));
    }
  }

  @override
  Future<Uint8List> loadImage(ShelfBook book, String src) async {
    final entry = _sources[book.origin];
    if (entry == null) throw const ContentLoadException.sourceMissing();
    try {
      return await _engine.image(entry.source, engineBookOf(book), src);
    } catch (e) {
      throw ContentLoadException(describeError(e));
    }
  }

  @override
  String? imageStyle(ShelfBook book) => _sources[book.origin]?.source.ruleContent['imageStyle'];

  /// 依次执行对这本书生效的规则（replace-rules「规则的作用范围」「执行替换」「超时停用」）：
  /// 普通文本在这里替换，正则交给 worker（设计 D2）；超时的规则跳过并停用（设计 D5）。
  @override
  Future<Purified> purify(ShelfBook book, ChapterText text) async {
    final disabled = <String>[];
    Future<String> apply(String input, bool Function(ReplaceRule rule) target) async {
      var result = input;
      for (final ReplaceRuleEntry(:rule) in _rules.entries) {
        // 每条执行前读当前的启用状态：别的章节刚因为超时停用的规则不再执行
        if (!target(rule) || !_rules.isEnabled(rule.id) || !_inScope(rule, book)) continue;
        if (!rule.isRegex) {
          result = result.replaceAll(rule.pattern, rule.replacement);
          continue;
        }
        try {
          result = await _engine.replace(result, rule);
        } on TaskTimeoutException {
          if (await _rules.disable(rule.id)) disabled.add(rule.name.isEmpty ? rule.pattern : rule.name);
        } catch (_) {
          // worker 异常退出等：这条规则不改变文字，章节照常显示
        }
      }
      return result;
    }

    final title = await apply(text.title, (rule) => rule.scopeTitle);
    final content = await apply(text.content, (rule) => rule.scopeContent);
    return (text: (title: title, content: content), disabled: disabled);
  }

  /// 作用范围为空或提到这本书（书名或书源地址），并且排除范围没有提到它。同 Legado 按 `LIKE` 查找。
  static bool _inScope(ReplaceRule rule, ShelfBook book) {
    bool mentions(String scope) => scope.contains(book.name) || scope.contains(book.origin);
    return (rule.scope.isEmpty || mentions(rule.scope)) && (rule.excludeScope.isEmpty || !mentions(rule.excludeScope));
  }

  @override
  ShelfRefresh refreshShelf(List<ShelfBook> books) => _ShelfRefresh(this, books);
}

final class _ShelfRefresh implements ShelfRefresh {
  _ShelfRefresh(OnlineContentSource owner, List<ShelfBook> books) {
    final pending = [
      for (final book in books)
        _refresh(owner, book).then((result) {
          if (!_batch.isStopped) _results.add(result);
        }, onError: (Object _) {}), // 只有停止时的取消错误会到这里
    ];
    unawaited(Future.wait(pending).whenComplete(_results.close));
  }

  final Batch _batch = Batch();
  final StreamController<TocRefreshResult> _results = StreamController();

  @override
  Stream<TocRefreshResult> get results => _results.stream;

  @override
  void stop() {
    _batch.stop();
    unawaited(_results.close());
  }

  Future<TocRefreshResult> _refresh(OnlineContentSource owner, ShelfBook book) async {
    final entry = owner._sources[book.origin];
    if (entry == null) return TocSourceMissing(book.bookUrl);
    try {
      final result = await owner._engine.chapterList(entry.source, engineBookOf(book), batch: _batch);
      return TocRefreshed(book.bookUrl, tocUpdateOf(result));
    } on TaskCancelledException {
      rethrow;
    } catch (e) {
      return TocRefreshFailed(book.bookUrl, describeError(e));
    }
  }
}
