import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rule_engine/rule_engine.dart';

import 'batch.dart';
import 'errors.dart';
import 'providers.dart';
import 'source_repository.dart';

/// 合并项在一个书源上的结果。
typedef SearchCandidate = ({SourceEntry source, SearchBook book});

/// 同名同作者的结果合并成的一项（book-search「合并同一本书」）。[results] 按完成的先后排列，展示用第一个。
final class MergedBook {
  MergedBook(this.name, this.author, {int order = 0}) : _order = order;

  final String name;
  final String author;

  /// 第一次出现的先后，书源数相同时先出现的在前。
  final int _order;
  final List<SearchCandidate> results = [];

  SearchBook get first => results.first.book;
}

typedef SearchFailure = ({String sourceName, String reason});

final class SearchState {
  const SearchState({
    this.key = '',
    this.books = const [],
    this.done = 0,
    this.total = 0,
    this.failures = const [],
    this.running = false,
    this.noSources = false,
  });

  final String key;
  final List<MergedBook> books;

  /// 已完成（成功或失败）的书源数和参与搜索的书源总数。
  final int done;
  final int total;
  final List<SearchFailure> failures;
  final bool running;

  /// 没有可以搜索的书源，没有发起搜索。
  final bool noSources;

  bool get finished => total > 0 && !running;

  SearchState copyWith({List<MergedBook>? books, int? done, List<SearchFailure>? failures, bool? running}) => SearchState(
    key: key,
    books: books ?? this.books,
    done: done ?? this.done,
    total: total,
    failures: failures ?? this.failures,
    running: running ?? this.running,
  );
}

/// 一次搜索一个 [Batch]；发起新搜索、停止、离开搜索页时取消。代数用来丢掉取消之后才到达的结果（设计 D7）。
final class SearchController extends AutoDisposeNotifier<SearchState> {
  Batch? _batch;
  int _generation = 0;
  final Map<(String, String), MergedBook> _merged = {};

  @override
  SearchState build() {
    ref.onDispose(() => _batch?.stop());
    return const SearchState();
  }

  void search(String input) {
    final key = input.trim();
    if (key.isEmpty) return;
    _cancel();
    final sources = [
      for (final entry in ref.read(sourceRepositoryProvider).entries)
        if (entry.searchable) entry,
    ];
    if (sources.isEmpty) {
      state = SearchState(key: key, noSources: true);
      return;
    }
    final generation = _generation;
    final batch = _batch = Batch();
    final engine = ref.read(sourceEngineProvider);
    state = SearchState(key: key, total: sources.length, running: true);
    for (final entry in sources) {
      engine.search(entry.source, key, batch).then(
        (books) => _complete(generation, entry, books, null),
        onError: (Object error) => _complete(generation, entry, const [], error),
      );
    }
  }

  /// 停止：没完成的书源被取消，已有的结果保留。
  void stop() {
    if (!state.running) return;
    _cancel();
    state = state.copyWith(running: false);
  }

  void _cancel() {
    _generation++;
    _batch?.stop();
    _batch = null;
    _merged.clear();
  }

  void _complete(int generation, SourceEntry entry, List<SearchBook> books, Object? error) {
    if (generation != _generation || error is TaskCancelledException) return;
    for (final book in books) {
      final key = (book.name.trim(), book.author.trim());
      final merged = _merged[key] ??= MergedBook(key.$1, key.$2, order: _merged.length);
      merged.results.add((source: entry, book: book));
    }
    final done = state.done + 1;
    state = state.copyWith(
      books: _sorted(state.key),
      done: done,
      failures: error == null
          ? null
          : [...state.failures, (sourceName: entry.source.bookSourceName, reason: describeError(error))],
      running: done < state.total,
    );
  }

  /// 三组依次排列：书名等于关键词、包含关键词、其它；组内书源数多的在前，相同时先出现的在前。
  List<MergedBook> _sorted(String key) {
    int group(MergedBook book) => book.name == key ? 0 : (book.name.contains(key) ? 1 : 2);
    return [..._merged.values]..sort(
      (a, b) => switch (group(a).compareTo(group(b))) {
        0 => switch (b.results.length.compareTo(a.results.length)) {
          0 => a._order.compareTo(b._order),
          final c => c,
        },
        final c => c,
      },
    );
  }
}

final searchControllerProvider = NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);
