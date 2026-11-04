import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/icons.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../reader_settings.dart';
import '../screen_brightness.dart';

/// 外观面板（reader「阅读设置」，redesign-minimal-ui 设计 D5）：亮度（只在能改亮度的平台上，add-reader-brightness 设计 D4），
/// 主题显示为它的底色色块，选中的有描边。
class AppearancePanel extends ConsumerWidget {
  const AppearancePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final colors = AppColors.of(context);
    final follow = settings.brightnessFollowSystem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.page, AppSpacing.page, AppSpacing.item),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ScreenBrightness.supported)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.item),
              child: Row(
                children: [
                  Icon(LucideIcons.sun, size: 20, color: colors.textSecondary),
                  Expanded(
                    child: Slider(
                      value: settings.brightness,
                      min: ReaderSettings.minBrightness,
                      max: ReaderSettings.maxBrightness,
                      semanticFormatterCallback: (value) => '亮度 ${(value * 100).round()}%',
                      // 跟随系统时不可拖动，和 Legado 一样
                      onChanged: follow ? null : (value) => notifier.update(settings.copyWith(brightness: value)),
                    ),
                  ),
                  ChoiceChip(
                    label: Text('跟随系统', style: TextStyle(color: follow ? colors.onAccent : colors.textPrimary)),
                    selected: follow,
                    onSelected: (value) => notifier.update(settings.copyWith(brightnessFollowSystem: value)),
                  ),
                ],
              ),
            ),
          PresetPicker<ReaderTheme>(
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
            onSelected: (theme) => notifier.update(settings.copyWith(theme: theme)),
          ),
        ],
      ),
    );
  }
}
