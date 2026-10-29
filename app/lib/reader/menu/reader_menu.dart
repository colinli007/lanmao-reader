import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/database.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../paged/chapter_window.dart';
import '../reader_settings.dart';
import '../toc_page.dart';
import 'appearance_panel.dart';
import 'layout_panel.dart';
import 'progress_panel.dart';

/// 菜单底栏上方的面板（reader「阅读菜单」）。
enum ReaderPanel { progress, appearance, layout }

/// 阅读菜单（redesign-minimal-ui 设计 D5）：顶栏只有返回，底栏四个图标。目录打开目录页，另外三个在底栏上方原地切换面板。
///
/// 只在菜单显示时构建：菜单收起时这个组件被销毁，打开的面板跟着清空。配色跟着正文主题的深浅。
class ReaderMenu extends ConsumerStatefulWidget {
  const ReaderMenu({super.key, required this.book, required this.chapters, required this.window});

  final ShelfBook book;
  final List<TocChapter> chapters;
  final ChapterWindow window;

  @override
  ConsumerState<ReaderMenu> createState() => _ReaderMenuState();
}

class _ReaderMenuState extends ConsumerState<ReaderMenu> {
  ReaderPanel? _panel;

  /// 选了一章就从章首开始（reader「章节切换」）。
  Future<void> _openToc() async {
    final window = widget.window;
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => TocPage(bookUrl: widget.book.bookUrl, bookName: widget.book.name, chapters: widget.chapters, current: window.chapter),
      ),
    );
    if (index != null) window.open(index);
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerSettingsProvider).effectiveTheme(MediaQuery.platformBrightnessOf(context));
    return Theme(
      data: appTheme(ThemeData.estimateBrightnessForColor(reader.background)),
      child: Builder(
        builder: (context) {
          final colors = AppColors.of(context);
          Widget item(IconData icon, String tooltip, ReaderPanel? panel) => IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: panel != null && panel == _panel ? colors.accent : colors.textPrimary),
            onPressed: panel == null ? _openToc : () => setState(() => _panel = _panel == panel ? null : panel),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: colors.background,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(height: 56, child: Row(children: [const SizedBox(width: 4), BackButton(color: colors.textPrimary)])),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Material(
                  color: colors.background,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        switch (_panel) {
                          null => const SizedBox.shrink(),
                          ReaderPanel.progress => ProgressPanel(window: widget.window, chapters: widget.chapters),
                          ReaderPanel.appearance => const AppearancePanel(),
                          ReaderPanel.layout => const LayoutPanel(),
                        },
                        if (_panel != null) Divider(color: colors.fill),
                        SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              item(LucideIcons.list, '目录', null),
                              item(LucideIcons.gitCommitHorizontal, '进度', ReaderPanel.progress),
                              item(LucideIcons.palette, '外观', ReaderPanel.appearance),
                              item(LucideIcons.aLargeSmall, '排版', ReaderPanel.layout),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
