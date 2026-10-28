import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import '../ui/cinema.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart';
import 'paged/chapter_window.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';
import 'toc_page.dart';

/// 阅读菜单（设计 D9）：夜墨主题按设计稿「阅读器 / 正文 · 影院」，通栏顶栏和深色控制面板；
/// 其余三种浅色主题按「阅读器 / 正文 · 过渡」，顶栏和控制面板都是暖墨色胶囊。
class ReaderMenu extends ConsumerWidget {
  const ReaderMenu({super.key, required this.book, required this.chapters, required this.window, required this.theme});

  final ShelfBook book;
  final List<TocChapter> chapters;
  final ChapterWindow window;

  /// 实际显示的阅读主题。
  final ReaderTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = theme.isDark ? _Palette.night : _Palette.ink;
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        if (theme.isDark)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(book: book, palette: palette),
          )
        else
          Positioned(
            top: padding.top,
            left: 12,
            right: 12,
            child: _TopBar(book: book, palette: palette),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: math.max(16, padding.bottom - 6),
          child: _Panel(
            palette: palette,
            child: _Controls(book: book, chapters: chapters, window: window, theme: theme, palette: palette),
          ),
        ),
      ],
    );
  }
}

/// 两套配色。
enum _Palette {
  night(panel: Color(0xF01E1E22), bar: Color(0xE017171A), text: Night.text, meta: Night.text3, label: Night.text2, button: Night.glass),
  ink(
    panel: Color(0xF21F1B16),
    bar: Color(0xF21F1B16),
    text: Color(0xFFF4EFE6),
    meta: Color(0xFF9A8E7E),
    label: Color(0xFFC9BBA7),
    button: Color(0x14FFFFFF),
  );

  const _Palette({
    required this.panel,
    required this.bar,
    required this.text,
    required this.meta,
    required this.label,
    required this.button,
  });

  final Color panel;
  final Color bar;
  final Color text;
  final Color meta;
  final Color label;
  final Color button;
}

class _Blur extends StatelessWidget {
  const _Blur({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: radius,
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: child),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.book, required this.palette});

  final ShelfBook book;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final night = palette == _Palette.night;
    Widget button(IconData icon, String tooltip, String feature) => GlassIconButton(
      icon: icon,
      tooltip: tooltip,
      size: night ? 36 : 40,
      blur: false,
      color: palette.button,
      iconColor: palette.text,
      onPressed: () => showNotDeveloped(context, feature),
    );
    final row = Row(
      spacing: night ? 12 : 8,
      children: [
        IconButton(
          tooltip: '返回',
          visualDensity: VisualDensity.compact,
          icon: Icon(LucideIcons.chevronLeft, size: night ? 24 : 22, color: palette.text),
          onPressed: () => Navigator.maybePop(context),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: night ? 2 : 1,
            children: [
              Text(
                book.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: night ? sans(15, weight: FontWeight.w700) : serif(15, color: palette.text),
              ),
              GestureDetector(
                onTap: () => showNotDeveloped(context, '阅读页换源'),
                child: Text(
                  '${book.originName} · 换源',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(night ? 11 : 10, color: palette.meta),
                ),
              ),
            ],
          ),
        ),
        if (night) button(LucideIcons.headphones, '听书', '听书'),
        button(LucideIcons.bookmark, '书签', '书签'),
        button(LucideIcons.ellipsis, '更多', '更多操作'),
      ],
    );
    if (night) {
      return _Blur(
        radius: BorderRadius.zero,
        child: Container(
          padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top, 16, 12),
          decoration: BoxDecoration(
            color: palette.bar,
            border: const Border(bottom: BorderSide(color: Night.line)),
          ),
          child: row,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x401F1B16), offset: Offset(0, 10), blurRadius: 24)],
      ),
      child: _Blur(
        radius: BorderRadius.circular(28),
        child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 8), color: palette.bar, child: row),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.palette, required this.child});

  final _Palette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final night = palette == _Palette.night;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: night ? const Color(0xB3000000) : const Color(0x521F1B16), offset: const Offset(0, 16), blurRadius: 40),
        ],
      ),
      child: _Blur(
        radius: BorderRadius.circular(28),
        child: Container(
          padding: night ? const EdgeInsets.fromLTRB(20, 20, 20, 16) : const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(28),
            border: night ? Border.all(color: Night.line) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 控制面板的内容：进度、章节进度条、（夜墨）主题和字号、四个操作。
class _Controls extends ConsumerStatefulWidget {
  const _Controls({required this.book, required this.chapters, required this.window, required this.theme, required this.palette});

  final ShelfBook book;
  final List<TocChapter> chapters;
  final ChapterWindow window;
  final ReaderTheme theme;
  final _Palette palette;

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  /// 拖动进度条时停在的章节序号（从 0 开始，不算卷）。
  int? _dragging;

  /// 不是卷的章节在目录里的下标。
  late final List<int> _readable = [
    for (final (index, chapter) in widget.chapters.indexed)
      if (!chapter.isVolume) index,
  ];

  /// 每分钟读的字数，估计本章的阅读时间用。
  static const _charsPerMinute = 400;

  ChapterWindow get _window => widget.window;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _window, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final palette = widget.palette;
    final night = palette == _Palette.night;
    final total = _readable.length;
    final ordinal = _readable.indexOf(_window.chapter).clamp(0, math.max(total - 1, 0));
    final paragraphs = _window.layoutOf(_window.chapter)?.chapter.paragraphs;
    final length = paragraphs == null || paragraphs.isEmpty ? 0 : paragraphs.last.offset + paragraphs.last.text.length;
    final within = length == 0 ? 0.0 : (_window.offset / length).clamp(0.0, 1.0);
    final percent = total == 0 ? 0.0 : (ordinal + within) / total * 100;
    final dragging = _dragging;
    final remain = dragging != null
        ? widget.chapters[_readable[dragging]].title
        : [if (length > 0) '本章约 ${(length / _charsPerMinute).ceil()} 分钟', '余 ${total - ordinal - 1} 章'].join(' · ');
    final previous = _window.neighbor(_window.chapter, -1);
    final next = _window.neighbor(_window.chapter, 1);

    Widget skip({required bool forward, required int? target}) {
      final label = forward ? '下一章' : '上一章';
      final color = target == null ? palette.meta : (night ? Night.text2 : (forward ? palette.text : palette.label));
      final onTap = target == null ? null : () => _window.open(target);
      if (night) {
        return IconButton(
          tooltip: label,
          visualDensity: VisualDensity.compact,
          icon: Icon(forward ? LucideIcons.skipForward : LucideIcons.skipBack, size: 16, color: color),
          onPressed: onTap,
        );
      }
      return TextButton(
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.all(4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        child: Text(label, style: sans(12, color: color)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: sans(night ? 20 : 18, color: palette.text, weight: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                remain,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11, color: palette.meta),
              ),
            ),
          ],
        ),
        SizedBox(height: night ? 10 : 16),
        Row(
          children: [
            skip(forward: false, target: previous),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: Night.amber,
                  inactiveTrackColor: night ? Night.glass : const Color(0x24FFFFFF),
                  thumbColor: palette.text,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2, pressedElevation: 4),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  label: '章节进度',
                  value: (dragging ?? ordinal).toDouble(),
                  max: math.max(total - 1, 1).toDouble(),
                  onChanged: total < 2 ? null : (value) => setState(() => _dragging = value.round()),
                  onChangeEnd: (value) {
                    setState(() => _dragging = null);
                    final target = _readable[value.round()];
                    if (target != _window.chapter) _window.open(target);
                  },
                ),
              ),
            ),
            skip(forward: true, target: next),
          ],
        ),
        if (night) ...[const SizedBox(height: 18), _Appearance(theme: widget.theme)],
        SizedBox(height: night ? 18 : 16),
        const Divider(height: 1, color: Night.line),
        SizedBox(height: night ? 16 : 14),
        Row(
          children: [
            _action(LucideIcons.list, '目录', _openToc),
            _action(night ? LucideIcons.audioLines : LucideIcons.headphones, '朗读', () => showNotDeveloped(context, '朗读')),
            _action(night ? LucideIcons.sun : LucideIcons.moon, night ? '日间' : '夜间', _toggleNight),
            _action(night ? LucideIcons.settings2 : LucideIcons.type, '设置', () => showReaderSettings(context)),
          ],
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(icon, size: 20, color: widget.palette.text),
          Text(label, style: sans(11, color: widget.palette.label)),
        ],
      ),
    ),
  );

  /// 目录选章：从章首开始（reader「章节切换」）。
  Future<void> _openToc() async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => TocPage(book: widget.book, chapters: widget.chapters, current: _window.chapter),
      ),
    );
    if (index != null) _window.open(index);
  }

  /// 日间、夜间切换：夜间就是夜墨主题；切回日间时用素白，并关掉跟随系统深色，否则系统是深色时切不回来。
  void _toggleNight() {
    final notifier = ref.read(readerSettingsProvider.notifier);
    final settings = ref.read(readerSettingsProvider);
    notifier.update(
      widget.theme.isDark
          ? settings.copyWith(theme: settings.theme.isDark ? ReaderTheme.light : settings.theme, followSystemDark: false)
          : settings.copyWith(theme: ReaderTheme.dark),
    );
  }
}

/// 夜墨面板里的主题色点和字号加减。
class _Appearance extends ConsumerWidget {
  const _Appearance({required this.theme});

  final ReaderTheme theme;

  /// 色点的顺序按设计稿。
  static const _order = [ReaderTheme.dark, ReaderTheme.sepia, ReaderTheme.bamboo, ReaderTheme.light];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final size = settings.fontSize;
    void setSize(double value) =>
        notifier.update(settings.copyWith(fontSize: value.clamp(ReaderSettings.minFontSize, ReaderSettings.maxFontSize)));
    return Row(
      children: [
        for (final option in _order) ...[
          Tooltip(
            message: option.label,
            child: GestureDetector(
              // 选了浅色主题而系统是深色时，关掉跟随系统深色，否则选了也看不到
              onTap: () => notifier.update(settings.copyWith(theme: option, followSystemDark: option.isDark && settings.followSystemDark)),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: option.background,
                  shape: BoxShape.circle,
                  border: option == theme ? Border.all(color: Night.amber, width: 2) : Border.all(color: const Color(0x33FFFFFF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const ShapeDecoration(color: Night.glass, shape: StadiumBorder()),
          child: Row(
            children: [
              _SizeButton(label: 'A', fontSize: 12, tooltip: '字号减小', onTap: () => setSize(size - 1)),
              Text('${size.round()}', style: sans(13, weight: FontWeight.w700)),
              _SizeButton(label: 'A', fontSize: 17, tooltip: '字号增大', onTap: () => setSize(size + 1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({required this.label, required this.fontSize, required this.tooltip, required this.onTap});

  final String label;
  final double fontSize;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Text(label, style: sans(fontSize, color: Night.text2)),
        ),
      ),
    ),
  );
}
