import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/icons.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../reader_settings.dart';

/// 外观面板（reader「阅读设置」，redesign-minimal-ui 设计 D5）：主题显示为它的底色色块，选中的有描边。
class AppearancePanel extends ConsumerWidget {
  const AppearancePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.page, AppSpacing.page, AppSpacing.item),
      child: PresetPicker<ReaderTheme>(
        options: [
          for (final theme in ReaderTheme.values)
            (
              value: theme,
              label: '${theme.label}主题',
              color: theme.background,
              child: theme == ReaderTheme.dark ? Icon(LucideIcons.moon, size: 16, color: theme.foreground) : const SizedBox.shrink(),
            ),
        ],
        selected: settings.theme,
        onSelected: (theme) => ref.read(readerSettingsProvider.notifier).update(settings.copyWith(theme: theme)),
      ),
    );
  }
}
