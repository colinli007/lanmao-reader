import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_source.dart';
import '../library/providers.dart';
import '../library/relocate.dart';
import '../storage/database.dart';

final class ShelfRefreshState {
  const ShelfRefreshState({this.running = false, this.done = 0, this.total = 0, this.marks = const {}});

  final bool running;
  final int done;
  final int total;

  /// 本次运行里更新失败或书源不存在的书：书籍地址到原因。不落盘。
  final Map<String, String> marks;
}

/// 下拉刷新书架：更新每本书的目录（bookshelf「更新目录」）。成功的在一个事务里替换目录、重新定位当前章节；
/// 失败的保留原目录并标出原因。
final class ShelfRefreshController extends Notifier<ShelfRefreshState> {
  ShelfRefresh? _refresh;

  @override
  ShelfRefreshState build() => const ShelfRefreshState();

  Future<void> refresh() async {
    if (state.running) return;
    final db = ref.read(databaseProvider);
    final books = [for (final entry in await db.shelf()) entry.book];
    if (books.isEmpty) return;
    final marks = {...state.marks}..removeWhere((url, _) => books.any((b) => b.bookUrl == url));
    state = ShelfRefreshState(running: true, total: books.length, marks: marks);
    final refresh = _refresh = ref.read(contentSourceProvider).refreshShelf(books);
    await for (final result in refresh.results) {
      switch (result) {
        case TocRefreshed(:final bookUrl, :final update):
          await _apply(db, bookUrl, update);
        case TocRefreshFailed(:final bookUrl, :final message):
          marks[bookUrl] = message;
        case TocSourceMissing(:final bookUrl):
          marks[bookUrl] = '书源不存在';
      }
      state = ShelfRefreshState(running: true, done: state.done + 1, total: state.total, marks: {...marks});
    }
    _refresh = null;
    state = ShelfRefreshState(done: state.done, total: state.total, marks: {...marks});
  }

  /// 停止：没完成的书不再更新，原目录不变。
  void stop() => _refresh?.stop();

  Future<void> _apply(AppDatabase db, String bookUrl, TocUpdate update) async {
    final book = await db.getBook(bookUrl);
    if (book == null) return; // 更新期间被移出了书架
    final index = relocateChapter(update.chapters, index: book.durChapterIndex, url: book.durChapterUrl);
    await db.replaceToc(
      bookUrl,
      update.chapters,
      latestChapterTitle: update.latestChapterTitle,
      sourceData: update.sourceData,
      current: (index: index, title: update.chapters.isEmpty ? book.durChapterTitle : update.chapters[index].title),
    );
  }
}

final shelfRefreshProvider = NotifierProvider<ShelfRefreshController, ShelfRefreshState>(ShelfRefreshController.new);

final shelfProvider = StreamProvider<List<ShelfEntry>>((ref) => ref.watch(databaseProvider).watchShelf());
