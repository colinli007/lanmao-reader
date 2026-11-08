import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/content_source.dart';
import '../library/providers.dart';
import '../storage/database.dart';
import 'chapter_format.dart';
import 'content_images.dart';
import 'layout/chapter_layout.dart';
import 'layout/page_painter.dart';
import 'menu/reader_menu.dart';
import 'paged/chapter_window.dart';
import 'paged/paged_view.dart';
import 'reader_fonts.dart';
import 'reader_settings.dart';
import 'screen_awake.dart';
import 'scroll/scroll_view.dart';

/// 阅读页：按翻页方式显示分页视图或滚动视图，两者共用一个三章窗口（add-paged-reader 设计 D1、D9）。
///
/// [startAt] 不为空时从这一章的章首开始（详情页的目录选章、第一次阅读），否则从保存的进度继续。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.bookUrl, this.startAt, this.onChangeSource});

  final String bookUrl;
  final int? startAt;

  /// 由书源模块提供导航，阅读器只接收换源后的书籍地址。
  final Future<String?> Function(BuildContext context, String bookUrl)? onChangeSource;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late String _bookUrl = widget.bookUrl;
  late int? _startAt = widget.startAt;

  Future<void> _changeSource() async {
    final changed = await widget.onChangeSource!(context, _bookUrl);
    if (!mounted || changed == null || changed == _bookUrl) return;
    setState(() {
      _bookUrl = changed;
      _startAt = null;
    });
  }

  @override
  Widget build(BuildContext context) => _ReaderSession(
    key: ValueKey(_bookUrl),
    bookUrl: _bookUrl,
    startAt: _startAt,
    onChangeSource: widget.onChangeSource == null ? null : _changeSource,
  );
}

/// 每个书籍地址独立持有窗口、图片和请求。换源销毁旧会话，迟到的结果不能混入新书。
class _ReaderSession extends ConsumerStatefulWidget {
  const _ReaderSession({super.key, required this.bookUrl, this.startAt, this.onChangeSource});

  final String bookUrl;
  final int? startAt;
  final Future<void> Function()? onChangeSource;

  @override
  ConsumerState<_ReaderSession> createState() => _ReaderSessionState();
}

class _ReaderSessionState extends ConsumerState<_ReaderSession> {
  late final AppDatabase _db = ref.read(databaseProvider);
  late final BookContentSource _source = ref.read(contentSourceProvider);
  late final ScreenAwake _screen = ref.read(screenAwakeProvider);
  final _menu = ValueNotifier(false);
  late final AppLifecycleListener _lifecycle;

  ShelfBook? _book;
  List<TocChapter> _chapters = const [];

  /// 第一次拿到正文区域的尺寸时创建（排版要用）。
  ChapterWindow? _window;

  /// 这本书的正文图片，和窗口一起创建、一起释放。
  ContentImages? _images;

  /// 上次保存进度时的章节：窗口换了章就立即保存，同一章里的移动 2 秒防抖保存（设计 D13）。
  int? _savedChapter;
  Timer? _saveTimer;
  bool _changingSource = false;

  /// 进行中的正文请求，按章节地址；窗口里的三章共用，同一章同时只有一个。
  final Map<String, Future<ChapterText>> _loading = {};

  /// app 在前台：退到后台时恢复系统的熄屏设置（complete-reader-settings 设计 D4）。
  bool _foreground = true;

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
    _open();
  }

  /// 阅读页显示、app 在前台时：设置打开就屏幕常亮（reader「屏幕常亮」）。
  void _updateScreen() {
    final settings = ref.read(readerSettingsProvider);
    _screen.set(_foreground && settings.keepScreenOn);
  }

  @override
  void dispose() {
    _screen.set(false);
    _saveProgress();
    _lifecycle.dispose();
    _window?.dispose();
    _images?.dispose();
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
    final images = _images = ContentImages(
      db: _db,
      source: _source,
      book: book,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final window = ChapterWindow(chapters: _chapters, load: _formatted, spec: spec, images: images);
    final startAt = widget.startAt;
    if (startAt != null) {
      window.open(startAt.clamp(0, _chapters.length - 1));
    } else {
      window.open(book.durChapterIndex.clamp(0, _chapters.length - 1), offset: book.durChapterPos);
    }
    window.addListener(_onWindow);
    // 这一帧结束后：按要打开的位置保存一次（同时更新最近阅读时间），并重建一次，让菜单和目录用上窗口
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateScreen();
        unawaited(_saveProgress());
        setState(() {});
      }
    });
    return window;
  }

  /// 正文先按替换净化规则处理再排版，缓存里保存的是原文（reader「替换净化」，add-replace-rules 设计 D1）。
  Future<FormattedChapter> _formatted(int index) async {
    final text = await _text(index);
    if (!mounted) throw StateError('阅读已结束');
    final purified = await _source.purify(_book!, (title: text.title.isEmpty ? _chapters[index].title : text.title, content: text.content));
    if (mounted) {
      for (final name in purified.disabled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('替换规则「$name」超时，已停用')));
      }
    }
    final chapter = formatChapter(purified.text.title, purified.text.content);
    // 排版前先取到这一章的图片、量出尺寸（add-content-images 设计 D1）
    final sources = imageSourcesOf(chapter);
    if (sources.isEmpty) return chapter;
    final sizes = await _images!.prepare(sources);
    return arrangeImages(chapter, sizes, style: _source.imageStyle(_book!));
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
        // 换源会删除旧书；网络结果晚到时不能重新留下旧书的缓存。
        await _db.transaction(() async {
          if (await _db.getBook(book.bookUrl) != null) {
            await _db.putContent(ContentRow(bookUrl: book.bookUrl, chapterUrl: chapter.url, title: text.title, content: text.content));
          }
        });
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

  Future<void> _saveProgress() async {
    final book = _book;
    final window = _window;
    if (book == null || window == null) return;
    _saveTimer?.cancel();
    final index = window.chapter;
    final chapter = _chapters[index];
    _savedChapter = index;
    await _db.saveProgress(book.bookUrl, index: index, url: chapter.url, title: chapter.title, position: window.offset, now: DateTime.now());
  }

  Future<void> _changeSource() async {
    if (_changingSource) return;
    final route = ModalRoute.of(context);
    setState(() => _changingSource = true);
    try {
      // 不等两秒防抖：候选页按数据库里的最新位置对齐。
      await _saveProgress();
      if (mounted && route?.isCurrent == true) await widget.onChangeSource!();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开换源，请重试')));
    } finally {
      if (mounted) setState(() => _changingSource = false);
    }
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    ref.listen(
      readerSettingsProvider.select((settings) => settings.keepScreenOn),
      (_, _) => _updateScreen(),
    );
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.effectiveTheme(MediaQuery.platformBrightnessOf(context));
    // 花火 1.3.3 的阅读遮罩：(1 - brightness) / 2；withAlpha 保持旧版 withOpacity 的 8 位舍入。
    final dimming = settings.brightnessFollowSystem ? 0.0 : (1 - settings.brightness.clamp(0.0, 1.0)) / 2;
    final book = _book;
    // 正文背景铺到状态栏后面，状态栏图标的深浅跟着它；菜单的配色也跟着正文主题的深浅（redesign-minimal-ui 设计 D5）
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
            if (dimming > 0)
              IgnorePointer(
                child: ColoredBox(key: const ValueKey('reader-dimming'), color: Colors.black.withAlpha((dimming * 255).round())),
              ),
            ValueListenableBuilder(
              valueListenable: _menu,
              builder: (context, menu, _) => menu && book != null && _window != null
                  ? ReaderMenu(
                      book: book,
                      chapters: _chapters,
                      window: _window!,
                      onChangeSource: widget.onChangeSource == null ? null : _changeSource,
                      changingSource: _changingSource,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ReaderSettings settings, ReaderTheme theme) {
    final fontFamily = ref.watch(readerFontsProvider).familyFor(settings.fontId);
    final insets = PageGeometry.bodyInsets(MediaQuery.paddingOf(context), settings.margin);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 分页和滚动用同一个排版参数（滚动只用宽度），切换翻页方式时排版结果直接复用
        final spec = LayoutSpec(
          fontFamily: fontFamily,
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
