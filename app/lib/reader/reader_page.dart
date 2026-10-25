import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_source.dart';
import '../library/providers.dart';
import '../storage/database.dart';
import 'chapter_format.dart';
import 'chapter_list.dart';
import 'layout/chapter_layout.dart';
import 'layout/page_painter.dart';
import 'paged/chapter_window.dart';
import 'paged/paged_view.dart';
import 'reader_settings.dart';
import 'scroll/scroll_view.dart';

/// 阅读页：按翻页方式显示分页视图或滚动视图，两者共用一个三章窗口（add-paged-reader 设计 D1、D9）。
///
/// [startAt] 不为空时从这一章的章首开始（详情页的目录选章、第一次阅读），否则从保存的进度继续。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookUrl, this.startAt});

  final String bookUrl;
  final int? startAt;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final AppDatabase _db = ref.read(databaseProvider);
  late final BookContentSource _source = ref.read(contentSourceProvider);
  final _scaffold = GlobalKey<ScaffoldState>();
  final _menu = ValueNotifier(false);
  late final AppLifecycleListener _lifecycle;

  ShelfBook? _book;
  List<TocChapter> _chapters = const [];

  /// 第一次拿到正文区域的尺寸时创建（排版要用）。
  ChapterWindow? _window;

  /// 上次保存进度时的章节：窗口换了章就立即保存，同一章里的移动 2 秒防抖保存（设计 D13）。
  int? _savedChapter;
  Timer? _saveTimer;

  /// 进行中的正文请求，按章节地址；窗口里的三章共用，同一章同时只有一个。
  final Map<String, Future<ChapterText>> _loading = {};

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onInactive: _saveProgress, onHide: _saveProgress);
    _open();
  }

  @override
  void dispose() {
    _saveProgress();
    _lifecycle.dispose();
    _window?.dispose();
    _menu.dispose();
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
  }

  /// 第一次布局时创建窗口，打开要读的章节。在 LayoutBuilder 里调用，所以先打开再挂监听，不在构建期间 setState。
  ChapterWindow _createWindow(LayoutSpec spec) {
    final book = _book!;
    final window = ChapterWindow(chapters: _chapters, load: _formatted, spec: spec);
    final startAt = widget.startAt;
    if (startAt != null) {
      window.open(startAt.clamp(0, _chapters.length - 1));
    } else {
      window.open(book.durChapterIndex.clamp(0, _chapters.length - 1), offset: book.durChapterPos);
    }
    window.addListener(_onWindow);
    // 这一帧结束后：按要打开的位置保存一次（同时更新最近阅读时间），并重建一次，让菜单和目录用上窗口
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_saveProgress);
    });
    return window;
  }

  /// 正文先按替换净化规则处理再排版，缓存里保存的是原文（reader「替换净化」，add-replace-rules 设计 D1）。
  Future<FormattedChapter> _formatted(int index) async {
    final text = await _text(index);
    final purified = await _source.purify(_book!, (title: text.title.isEmpty ? _chapters[index].title : text.title, content: text.content));
    if (mounted) {
      for (final name in purified.disabled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('替换规则「$name」超时，已停用')));
      }
    }
    return formatChapter(purified.text.title, purified.text.content);
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

  /// 换了章：立即保存，菜单里的章节名、目录标记跟着变；同一章里翻页或滚动：2 秒内没有再动时保存。
  void _onWindow() {
    if (_window!.chapter != _savedChapter) {
      _saveProgress();
      setState(() {});
    } else {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 2), _saveProgress);
    }
  }

  void _saveProgress() {
    final book = _book;
    final window = _window;
    if (book == null || window == null) return;
    _saveTimer?.cancel();
    final index = window.chapter;
    final chapter = _chapters[index];
    _savedChapter = index;
    _db.saveProgress(book.bookUrl, index: index, url: chapter.url, title: chapter.title, position: window.offset, now: DateTime.now());
  }

  /// 菜单和目录换章：从章首开始（reader「章节切换」）。
  void _go(int index) => _window?.open(index);

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.effectiveTheme(MediaQuery.platformBrightnessOf(context));
    final book = _book;
    final window = _window;
    // 正文背景铺到状态栏后面，状态栏图标的深浅跟着它；菜单打开时盖在上面的 AppBar 用它自己的
    final background = ThemeData.estimateBrightnessForColor(theme.background);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarBrightness: background,
        statusBarIconBrightness: background == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        key: _scaffold,
        backgroundColor: theme.background,
        drawer: window == null
            ? null
            : Drawer(
                child: SafeArea(
                  child: ChapterList(
                    chapters: _chapters,
                    current: window.chapter,
                    onSelect: (index) {
                      Navigator.pop(context);
                      _go(index);
                    },
                  ),
                ),
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (book == null) Center(child: CircularProgressIndicator(color: theme.foreground)) else _content(settings, theme),
            ValueListenableBuilder(
              valueListenable: _menu,
              builder: (context, menu, _) => menu && book != null && _window != null
                  ? Stack(fit: StackFit.expand, children: _menuBars(book, _window!))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ReaderSettings settings, ReaderTheme theme) {
    final insets = PageGeometry.bodyInsets(MediaQuery.paddingOf(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        // 分页和滚动用同一个排版参数（滚动只用宽度），切换翻页方式时排版结果直接复用
        final spec = LayoutSpec(
          fontSize: settings.fontSize,
          lineHeight: settings.lineHeight,
          size: insets.deflateSize(constraints.biggest),
        );
        final window = _window ??= _createWindow(spec);
        window.resize(spec);
        return settings.pageMode == PageMode.scroll
            ? ScrollReaderView(window: window, theme: theme, menu: _menu)
            : PagedView(window: window, mode: settings.pageMode, theme: theme, insets: insets, menu: _menu);
      },
    );
  }

  List<Widget> _menuBars(ShelfBook book, ChapterWindow window) {
    final previous = window.neighbor(window.chapter, -1);
    final next = window.neighbor(window.chapter, 1);
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
              Text(_chapters[window.chapter].title, style: Theme.of(context).textTheme.bodySmall),
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
          spacing: 8,
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
            SegmentedButton<PageMode>(
              segments: [for (final mode in PageMode.values) ButtonSegment(value: mode, label: Text(mode.label))],
              selected: {settings.pageMode},
              onSelectionChanged: (selection) => notifier.update(settings.copyWith(pageMode: selection.single)),
            ),
            SwitchListTile(
              title: const Text('跟随系统深色'),
              value: settings.followSystemDark,
              onChanged: (value) => notifier.update(settings.copyWith(followSystemDark: value)),
            ),
          ],
        ),
      ),
    );
  }
}
