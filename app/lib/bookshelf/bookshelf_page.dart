import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../library/providers.dart';
import '../online/book_detail_page.dart';
import '../online/change_source_page.dart';
import '../online/search_page.dart';
import '../reader/reader_route.dart';
import '../storage/database.dart';
import '../ui/cinema.dart';
import '../ui/icons.dart';
import '../ui/relative_time.dart';
import '../ui/widgets.dart';
import 'shelf_refresh.dart';

/// 书架（bookshelf，设计稿「书架 / 首页 · 影院」）：最近读的那本书做大图，下面是追更中和全部书架。
/// 点书继续阅读，长按打开菜单，下拉刷新更新目录。
class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

/// 全部书架的筛选。连载、本地还没有数据，点了只提示（proposal「暂未开发的功能」）。
enum _Filter { all, finished }

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    final refresh = ref.watch(shelfRefreshProvider);
    final controller = ref.read(shelfRefreshProvider.notifier);
    final hero = shelf.firstOrNull;
    final following = [
      for (final entry in shelf.skip(1))
        if (entry.book.durChapterUrl != null && entry.unread > 0) entry,
    ];
    final finished = [
      for (final entry in shelf)
        if (_isFinished(entry)) entry,
    ];
    final library = _filter == _Filter.all ? shelf : finished;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Night.bg,
        body: RefreshIndicator(
          onRefresh: controller.refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
            children: [
              if (hero == null)
                _EmptyShelf(header: _header(context, refresh, controller, shelf))
              else
                _Hero(entry: hero, mark: refresh.marks[hero.book.bookUrl], header: _header(context, refresh, controller, shelf)),
              if (refresh.running) _RefreshProgress(state: refresh, onStop: controller.stop),
              if (following.isNotEmpty) _Following(entries: following),
              if (shelf.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                  child: SectionHead(title: '全部书架', meta: '${shelf.length} 本', link: '排序', onLink: () => showNotDeveloped(context, '书架排序')),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    spacing: 8,
                    children: [
                      CinemaChip(
                        label: '全部',
                        count: shelf.length,
                        selected: _filter == _Filter.all,
                        onTap: () => setState(() => _filter = _Filter.all),
                      ),
                      CinemaChip(label: '连载', onTap: () => showNotDeveloped(context, '连载筛选')),
                      CinemaChip(label: '本地', onTap: () => showNotDeveloped(context, '本地书')),
                      CinemaChip(
                        label: '读完',
                        count: finished.length,
                        selected: _filter == _Filter.finished,
                        onTap: () => setState(() => _filter = _Filter.finished),
                      ),
                    ],
                  ),
                ),
                _Grid(entries: library, marks: refresh.marks),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 顶栏：标题、搜索、导入本地书（暂未开发）。桌面上用鼠标不方便下拉，多一个更新目录按钮，和下拉刷新是同一个操作。
  Widget _header(BuildContext context, ShelfRefreshState refresh, ShelfRefreshController controller, List<ShelfEntry> shelf) {
    final desktop = defaultTargetPlatform == TargetPlatform.macOS;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text('书架', style: sans(22, weight: FontWeight.w800)),
          ),
          if (desktop) ...[
            GlassIconButton(
              icon: LucideIcons.refreshCw,
              tooltip: '更新目录',
              onPressed: refresh.running || shelf.isEmpty ? null : controller.refresh,
            ),
            const SizedBox(width: 10),
          ],
          GlassIconButton(
            icon: LucideIcons.search,
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          ),
          const SizedBox(width: 10),
          GlassIconButton(icon: LucideIcons.plus, tooltip: '导入本地书', onPressed: () => showNotDeveloped(context, '导入本地书')),
        ],
      ),
    );
  }

  static bool _isFinished(ShelfEntry entry) => entry.book.durChapterUrl != null && entry.total > 0 && entry.unread == 0;
}

/// 已读的比例：当前章节之前读完的章节数除以总数，读到最后一章时是 1。
double _progressOf(ShelfEntry entry) => entry.total == 0 ? 0 : (entry.total - entry.unread) / entry.total;

void _read(BuildContext context, ShelfBook book) => openReader(context, bookUrl: book.bookUrl, coverUrl: book.coverUrl, title: book.name);

void _openDetail(BuildContext context, ShelfBook book) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.shelf(book.bookUrl)));

/// 继续阅读大图（Hero）：封面铺满，渐变压暗，下面是书名、当前章节、进度和按钮。
class _Hero extends StatelessWidget {
  const _Hero({required this.entry, required this.mark, required this.header});

  final ShelfEntry entry;
  final String? mark;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final top = MediaQuery.paddingOf(context).top;
    final lastRead = book.lastReadAt;
    final started = book.durChapterUrl != null;
    final progress = _progressOf(entry);
    final mark = this.mark;
    return SizedBox(
      height: top + 492,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (book.coverUrl case final url? when url.isNotEmpty)
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.2, 0.5, 0.78, 1],
                colors: [Color(0xB30C0C0E), Color(0x000C0C0E), Color(0x330C0C0E), Color(0xE60C0C0E), Night.bg],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const Spacer(),
                Row(
                  spacing: 8,
                  children: [
                    const _Dot(color: Night.amber),
                    Text(
                      lastRead == null ? '最近加入' : '继续阅读 · ${relativeTime(lastRead, DateTime.now())}',
                      style: sans(12, color: Night.amber, weight: FontWeight.w600, letterSpacing: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(44, letterSpacing: 2, height: 1.2)),
                const SizedBox(height: 6),
                Text(
                  [book.author, ?_firstKind(book.kind)].where((s) => s.isNotEmpty).join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: Night.text2),
                ),
                const SizedBox(height: 14),
                Text(book.durChapterTitle ?? book.latestChapterTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(15)),
                if (mark != null) ...[const SizedBox(height: 6), _FailureMark(mark: mark)],
                const SizedBox(height: 14),
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: ThinProgress(value: progress, track: const Color(0x26FFFFFF)),
                    ),
                    Text('${(progress * 100).floor()}%  ·  余 ${entry.unread} 章', style: sans(12, color: Night.text2)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: PillButton(icon: LucideIcons.play, label: started ? '继续阅读' : '开始阅读', onPressed: () => _read(context, book)),
                    ),
                    GlassIconButton(
                      icon: LucideIcons.info,
                      tooltip: '详情',
                      size: 50,
                      iconSize: 20,
                      onPressed: () => _openDetail(context, book),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类常是「仙侠,连载」这样几项连在一起，只取第一项。
String? _firstKind(String? kind) => kind?.split(RegExp(r'[,，\s]+')).firstWhere((s) => s.isNotEmpty, orElse: () => '');

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 120),
        const Icon(LucideIcons.libraryBig, size: 40, color: Night.text3),
        const SizedBox(height: 16),
        Text(
          '书架是空的，去搜索添加吧',
          textAlign: TextAlign.center,
          style: sans(14, color: Night.text2),
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 180,
            child: PillButton(
              icon: LucideIcons.search,
              label: '去搜索',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RefreshProgress extends StatelessWidget {
  const _RefreshProgress({required this.state, required this.onStop});

  final ShelfRefreshState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('正在更新目录 ${state.done}/${state.total}', style: sans(12, color: Night.text2)),
            ),
            TextButton(
              onPressed: onStop,
              child: Text('停止', style: sans(13, color: Night.amber)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ThinProgress(value: state.total == 0 ? 0 : state.done / state.total),
        ),
      ],
    ),
  );
}

/// 追更中：读过、还有未读章节的书，横向滑动。
class _Following extends StatelessWidget {
  const _Following({required this.entries});

  final List<ShelfEntry> entries;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHead(title: '追更中', meta: '${entries.length} 本有未读', link: '全部', onLink: () => showNotDeveloped(context, '追更列表')),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _RailBook(entry: entries[index]),
          ),
        ),
      ],
    ),
  );
}

/// 组件库「Book / 横滑」。
class _RailBook extends StatelessWidget {
  const _RailBook({required this.entry});

  final ShelfEntry entry;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    return GestureDetector(
      onTap: () => _read(context, book),
      onLongPress: () => _showBookMenu(context, book),
      child: SizedBox(
        width: 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Color(0x80000000), offset: Offset(0, 10), blurRadius: 24)],
              ),
              child: Stack(
                children: [
                  BookCover(url: book.coverUrl, title: book.name, width: 136, height: 196, radius: 10),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x000C0C0E), Color(0xB30C0C0E)],
                        ),
                      ),
                      child: Row(
                        spacing: 6,
                        children: [
                          const _Dot(color: Night.amber),
                          Text(
                            '${entry.unread} 章未读',
                            style: sans(11, color: Night.amber, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(14, weight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: Night.text3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全部书架：每行三本。
class _Grid extends StatelessWidget {
  const _Grid({required this.entries, required this.marks});

  final List<ShelfEntry> entries;
  final Map<String, String> marks;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(
      spacing: 22,
      children: [
        for (var row = 0; row < entries.length; row += 3)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 14,
            children: [
              for (var i = row; i < row + 3; i++)
                Expanded(
                  child: i < entries.length ? _GridBook(entry: entries[i], mark: marks[entries[i].book.bookUrl]) : const SizedBox(),
                ),
            ],
          ),
      ],
    ),
  );
}

/// 组件库「Book / 网格」：读过的显示进度条，读完、没开始的显示文字；更新失败时标出原因。
class _GridBook extends StatelessWidget {
  const _GridBook({required this.entry, required this.mark});

  final ShelfEntry entry;
  final String? mark;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final mark = this.mark;
    final started = book.durChapterUrl != null;
    final finished = _BookshelfPageState._isFinished(entry);
    return GestureDetector(
      onTap: () => _read(context, book),
      onLongPress: () => _showBookMenu(context, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => BookCover(url: book.coverUrl, title: book.name, width: constraints.maxWidth, radius: 8),
          ),
          const SizedBox(height: 8),
          Text(
            book.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (mark != null)
            _FailureMark(mark: mark)
          else if (started && !finished)
            ThinProgress(value: _progressOf(entry), height: 2, color: Night.text2)
          else
            Text(finished ? '已读完' : '未开始', style: sans(11, color: Night.text3)),
        ],
      ),
    );
  }
}

/// 本次更新失败或书源不存在：点击查看原因。
class _FailureMark extends StatelessWidget {
  const _FailureMark({required this.mark});

  final String mark;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mark))),
    child: Text(mark == '书源不存在' ? mark : '更新失败', style: sans(11, color: Night.bad)),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

enum _Action { detail, changeSource, remove }

/// 长按书打开的菜单：详情、换书源、移出书架。
Future<void> _showBookMenu(BuildContext context, ShelfBook book) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(16, weight: FontWeight.w700),
            ),
          ),
          for (final (action, icon, label) in const [
            (_Action.detail, LucideIcons.info, '详情'),
            (_Action.changeSource, LucideIcons.repeat, '换书源'),
            (_Action.remove, LucideIcons.trash2, '移出书架'),
          ])
            ListTile(
              leading: Icon(icon, size: 20, color: action == _Action.remove ? Night.bad : Night.text),
              title: Text(label, style: sans(15, color: action == _Action.remove ? Night.bad : Night.text)),
              onTap: () => Navigator.pop(context, action),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  switch (action) {
    case _Action.detail:
      _openDetail(context, book);
    case _Action.changeSource:
      await _changeSource(context, container.read(databaseProvider), book);
    case _Action.remove:
      await _remove(context, container.read(databaseProvider), book);
  }
}

/// 换书源成功后书架跟着数据库刷新，这里只提示换到了哪个书源。
Future<void> _changeSource(BuildContext context, AppDatabase db, ShelfBook book) async {
  final messenger = ScaffoldMessenger.of(context);
  final bookUrl = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ChangeSourcePage(bookUrl: book.bookUrl)));
  if (bookUrl == null) return;
  final changed = await db.getBook(bookUrl);
  messenger.showSnackBar(SnackBar(content: Text('已换到${changed!.originName}')));
}

Future<void> _remove(BuildContext context, AppDatabase db, ShelfBook book) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('把《${book.name}》移出书架？'),
      content: const Text('目录、已缓存的正文和阅读进度会一起删除。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移出')),
      ],
    ),
  );
  if (confirmed == true) await db.removeBook(book.bookUrl);
}
