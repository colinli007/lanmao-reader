import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_source.dart';
import '../library/providers.dart';
import '../storage/database.dart';
import 'chapter_format.dart';
import 'layout/chapter_layout.dart';
import 'layout/page_painter.dart';
import 'paged/chapter_window.dart';
import 'paged/paged_view.dart';
import 'reader_menu.dart';
import 'reader_settings.dart';
import 'screen_awake.dart';
import 'scroll/scroll_view.dart';

/// 阅读页：按翻页方式显示分页视图或滚动视图，两者共用一个三章窗口（add-paged-reader 设计 D1、D9）。
///
/// [startAt] 不为空时从这一章的章首开始（详情页的目录选章、第一次阅读），否则从保存的进度继续。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookUrl, this.startAt, this.introMenu = false});

  final String bookUrl;
  final int? startAt;

  /// 从「继续阅读」的转场进入（reader_route.dart）：正文显示后菜单先出现，2 秒后自动收起（redesign-cinema-ui 设计 D10）。
  final bool introMenu;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final AppDatabase _db = ref.read(databaseProvider);
  late final BookContentSource _source = ref.read(contentSourceProvider);
  late final ScreenAwake _screen = ref.read(screenAwakeProvider);
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

  /// app 在前台：退到后台时恢复系统的熄屏设置（complete-reader-settings 设计 D4）。
  bool _foreground = true;

  /// [ReaderPage.introMenu] 的自动收起；用户在这之前自己开关过菜单就不再收起。
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: _saveProgress,
      onHide: () {
        _saveProgress();
        _foreground = false;
        _updateScreen();
      },
      onShow: () {
        _foreground = true;
        _updateScreen();
      },
    );
    _updateScreen();
    if (widget.introMenu) _menu.value = true;
    _menu.addListener(() => _introTimer?.cancel());
    _open();
  }

  /// 阅读页显示、app 在前台、设置打开时屏幕常亮（reader「屏幕常亮」）。
  void _updateScreen() => _screen.set(_foreground && ref.read(readerSettingsProvider).keepScreenOn);

  @override
  void dispose() {
    _screen.set(false);
    _introTimer?.cancel();
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
    if (widget.introMenu) _introTimer = Timer(const Duration(seconds: 2), () => _menu.value = false);
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

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    ref.listen(readerSettingsProvider.select((settings) => settings.keepScreenOn), (_, _) => _updateScreen());
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.effectiveTheme(MediaQuery.platformBrightnessOf(context));
    final book = _book;
    final window = _window;
    // 正文背景铺到状态栏后面，状态栏图标的深浅跟着它
    final background = ThemeData.estimateBrightnessForColor(theme.background);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarBrightness: background,
        statusBarIconBrightness: background == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: theme.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (book == null) Center(child: CircularProgressIndicator(color: theme.foreground)) else _content(settings, theme),
            ValueListenableBuilder(
              valueListenable: _menu,
              builder: (context, menu, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: menu && book != null && window != null
                    ? ReaderMenu(book: book, chapters: _chapters, window: window, theme: theme)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ReaderSettings settings, ReaderTheme theme) {
    final insets = PageGeometry.bodyInsets(MediaQuery.paddingOf(context), settings.margin);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 分页和滚动用同一个排版参数（滚动只用宽度），切换翻页方式时排版结果直接复用
        final spec = LayoutSpec(
          fontSize: settings.fontSize,
          lineHeight: settings.lineHeight,
          size: insets.deflateSize(constraints.biggest),
          paragraphSpacingRatio: settings.paragraphSpacing,
          indentChars: settings.indent,
        );
        final window = _window ??= _createWindow(spec);
        window.resize(spec);
        return settings.pageMode == PageMode.scroll
            ? ScrollReaderView(window: window, theme: theme, margin: settings.margin, menu: _menu)
            : PagedView(window: window, mode: settings.pageMode, theme: theme, insets: insets, menu: _menu);
      },
    );
  }
}
