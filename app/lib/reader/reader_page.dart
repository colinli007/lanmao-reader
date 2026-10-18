import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_source.dart';
import '../library/providers.dart';
import '../storage/database.dart';
import 'chapter_format.dart';
import 'chapter_list.dart';
import 'reader_settings.dart';

/// 滚动阅读：一次显示一章（reader 规格，设计 D9）。
///
/// [startAt] 不为空时从这一章的章首开始（详情页的目录选章、第一次阅读），否则从保存的进度继续。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookUrl, this.startAt});

  final String bookUrl;
  final int? startAt;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

/// 一章的显示状态。
sealed class _ChapterState {
  const _ChapterState();
}

final class _Loading extends _ChapterState {
  const _Loading();
}

final class _Failed extends _ChapterState {
  const _Failed(this.message);

  final String message;
}

final class _Shown extends _ChapterState {
  const _Shown(this.chapter);

  final FormattedChapter chapter;
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final AppDatabase _db = ref.read(databaseProvider);
  late final BookContentSource _source = ref.read(contentSourceProvider);
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _column = GlobalKey();
  late final AppLifecycleListener _lifecycle;

  ShelfBook? _book;
  List<TocChapter> _chapters = const [];
  int _index = 0;
  _ChapterState _state = const _Loading();
  List<GlobalKey> _paragraphKeys = const [];

  /// 当前章节内的阅读位置（第一个可见段落的偏移），滚动停止时更新。
  int _position = 0;
  bool _menu = false;
  Timer? _saveTimer;

  /// 进行中的正文请求，按章节地址；阅读和预加载共用，同一章同时只有一个。
  final Map<String, Future<ChapterText>> _loading = {};

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onInactive: _saveProgress, onHide: _saveProgress);
    _open();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // 元素正在卸载，不再量布局，用滚动停止时记下的位置
    _saveProgress(measure: false);
    _lifecycle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final book = await _db.getBook(widget.bookUrl);
    final chapters = await _db.chaptersOf(widget.bookUrl);
    if (!mounted || book == null || chapters.isEmpty) return;
    setState(() {
      _book = book;
      _chapters = chapters;
    });
    final startAt = widget.startAt;
    if (startAt != null) {
      await _show(startAt.clamp(0, chapters.length - 1));
    } else {
      await _show(book.durChapterIndex.clamp(0, chapters.length - 1), position: book.durChapterPos);
    }
  }

  /// 打开第 [index] 章，停在包含 [position] 的段落（默认章首）。
  Future<void> _show(int index, {int position = 0}) async {
    final chapter = _chapters[index];
    setState(() {
      _index = index;
      _position = position;
      _state = const _Loading();
      _paragraphKeys = const [];
    });
    final _ChapterState state;
    if (chapter.isVolume) {
      state = _Shown((title: chapter.title, paragraphs: const []));
    } else {
      try {
        final text = await _text(index);
        state = _Shown(formatChapter(text.title.isEmpty ? chapter.title : text.title, text.content));
      } on ContentLoadException catch (e) {
        if (mounted && _index == index) setState(() => _state = _Failed(e.message));
        return;
      }
    }
    if (!mounted || _index != index) return;
    setState(() {
      _state = state;
      if (state case _Shown(:final chapter)) _paragraphKeys = [for (final _ in chapter.paragraphs) GlobalKey()];
    });
    _restorePosition();
    // 新章节还没布局，按要打开的位置保存（同时更新最近阅读时间）
    _saveProgress(measure: false);
    _preloadAfter(index);
  }

  /// 正文：先读缓存，没有时执行正文链路并写入缓存。
  Future<ChapterText> _text(int index) async {
    final chapter = _chapters[index];
    final cached = await _db.getContent(widget.bookUrl, chapter.url);
    if (cached != null) return (title: cached.title, content: cached.content);
    final book = _book!;
    if (!_source.hasSource(book.origin)) throw const ContentLoadException.sourceMissing();
    return _loading[chapter.url] ??= () async {
      try {
        final next = index + 1 < _chapters.length ? _chapters[index + 1] : null;
        final text = await _source.loadContent(book, chapter, next: next);
        await _db.putContent(ContentRow(bookUrl: book.bookUrl, chapterUrl: chapter.url, title: text.title, content: text.content));
        return text;
      } finally {
        _loading.remove(chapter.url);
      }
    }();
  }

  /// 预加载下一个不是卷的章节，失败不提示。
  void _preloadAfter(int index) {
    final next = _neighbor(index, 1);
    if (next != null) _text(next).ignore();
  }

  /// 上一章、下一章跳过卷。
  int? _neighbor(int index, int step) {
    for (var i = index + step; i >= 0 && i < _chapters.length; i += step) {
      if (!_chapters[i].isVolume) return i;
    }
    return null;
  }

  void _go(int index) {
    _saveProgress();
    _show(index);
  }

  // ---------------------------------------------------------------- 阅读位置

  /// 视口顶部所在的段落的偏移；还没有布局时返回上次记下的位置。
  int _visiblePosition() {
    final state = _state;
    final column = _column.currentContext?.findRenderObject() as RenderBox?;
    if (state is! _Shown || column == null || !_scroll.hasClients || state.chapter.paragraphs.isEmpty) return _position;
    final top = _scroll.offset;
    var position = 0;
    for (final (i, key) in _paragraphKeys.indexed) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) break;
      if (box.localToGlobal(Offset.zero, ancestor: column).dy > top + 1) break;
      position = state.chapter.paragraphs[i].offset;
    }
    return position;
  }

  /// 布局完成后把包含 [_position] 的段落滚到顶部。
  void _restorePosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _state;
      final column = _column.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || state is! _Shown || column == null || !_scroll.hasClients) return;
      if (_position == 0 || state.chapter.paragraphs.isEmpty) {
        _scroll.jumpTo(0);
        return;
      }
      final box = _paragraphKeys[paragraphAt(state.chapter.paragraphs, _position)].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final y = box.localToGlobal(Offset.zero, ancestor: column).dy;
      _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  void _saveProgress({bool measure = true}) {
    final book = _book;
    if (book == null || _chapters.isEmpty) return;
    if (measure) _position = _visiblePosition();
    final chapter = _chapters[_index];
    _db.saveProgress(book.bookUrl, index: _index, url: chapter.url, title: chapter.title, position: _position, now: DateTime.now());
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _position = _visiblePosition();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 2), _saveProgress);
    }
    return false;
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    ref.listen(readerSettingsProvider, (_, _) {
      // 改设置之前记下第一个可见段落，重排之后滚回去
      _position = _visiblePosition();
      _restorePosition();
    });
    final book = _book;
    final theme = settings.theme;
    return Scaffold(
      key: _scaffold,
      backgroundColor: theme.background,
      drawer: book == null
          ? null
          : Drawer(
              child: SafeArea(
                child: ChapterList(
                  chapters: _chapters,
                  current: _index,
                  onSelect: (index) {
                    Navigator.pop(context);
                    _go(index);
                  },
                ),
              ),
            ),
      body: Stack(
        // 铺满整页：章节很短时正文只有几行，点中部也要能打开菜单
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final size = MediaQuery.sizeOf(context);
              final p = details.localPosition;
              final central = p.dx > size.width / 3 && p.dx < size.width * 2 / 3 && p.dy > size.height / 3 && p.dy < size.height * 2 / 3;
              if (central) setState(() => _menu = !_menu);
            },
            child: SafeArea(child: _content(settings)),
          ),
          if (_menu && book != null) ..._menuBars(book),
        ],
      ),
    );
  }

  Widget _content(ReaderSettings settings) {
    final color = settings.theme.foreground;
    final body = TextStyle(fontSize: settings.fontSize, height: settings.lineHeight, color: color);
    switch (_state) {
      case _Loading():
        return Center(child: CircularProgressIndicator(color: color));
      case _Failed(:final message):
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(16), child: Text(message, style: TextStyle(color: color))),
              FilledButton(onPressed: () => _show(_index, position: _position), child: const Text('重试')),
            ],
          ),
        );
      case _Shown(:final chapter):
        final previous = _neighbor(_index, -1);
        final next = _neighbor(_index, 1);
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              key: _column,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (previous != null)
                  Align(child: TextButton(onPressed: () => _go(previous), child: const Text('上一章'))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(chapter.title, style: body.copyWith(fontSize: settings.fontSize * 1.3, fontWeight: FontWeight.w600)),
                ),
                for (final (i, paragraph) in chapter.paragraphs.indexed)
                  Padding(
                    key: _paragraphKeys[i],
                    padding: EdgeInsets.only(bottom: settings.fontSize * 0.6),
                    child: Text(paragraph.text, style: body),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Align(
                    child: next == null
                        ? Text('已是最后一章', style: TextStyle(color: color))
                        : FilledButton(onPressed: () => _go(next), child: const Text('下一章')),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  List<Widget> _menuBars(ShelfBook book) {
    final previous = _neighbor(_index, -1);
    final next = _neighbor(_index, 1);
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AppBar(
          // 页面有目录抽屉，不写的话这里会显示成打开抽屉的按钮
          leading: const BackButton(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.name),
              Text(_chapters[_index].title, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: previous == null ? null : () => _go(previous), child: const Text('上一章')),
                IconButton(tooltip: '目录', icon: const Icon(Icons.list), onPressed: () => _scaffold.currentState?.openDrawer()),
                IconButton(tooltip: '阅读设置', icon: const Icon(Icons.text_fields), onPressed: _openSettings),
                TextButton(onPressed: next == null ? null : () => _go(next), child: const Text('下一章')),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  void _openSettings() => showModalBottomSheet<void>(context: context, builder: (_) => const _SettingsSheet());
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(width: 72, child: Text('字号 ${settings.fontSize.round()}')),
                Expanded(
                  child: Slider(
                    label: '字号',
                    value: settings.fontSize,
                    min: ReaderSettings.minFontSize,
                    max: ReaderSettings.maxFontSize,
                    divisions: (ReaderSettings.maxFontSize - ReaderSettings.minFontSize).round(),
                    onChanged: (value) => notifier.update(settings.copyWith(fontSize: value.roundToDouble())),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(width: 72, child: Text('行距 ${settings.lineHeight.toStringAsFixed(1)}')),
                Expanded(
                  child: Slider(
                    label: '行距',
                    value: settings.lineHeight,
                    min: ReaderSettings.minLineHeight,
                    max: ReaderSettings.maxLineHeight,
                    divisions: ((ReaderSettings.maxLineHeight - ReaderSettings.minLineHeight) * 10).round(),
                    onChanged: (value) => notifier.update(settings.copyWith(lineHeight: (value * 10).round() / 10)),
                  ),
                ),
              ],
            ),
            SegmentedButton<ReaderTheme>(
              segments: [for (final theme in ReaderTheme.values) ButtonSegment(value: theme, label: Text(theme.label))],
              selected: {settings.theme},
              onSelectionChanged: (selection) => notifier.update(settings.copyWith(theme: selection.single)),
            ),
          ],
        ),
      ),
    );
  }
}
