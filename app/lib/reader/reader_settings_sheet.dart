import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reader_settings.dart';

/// 阅读设置面板。项多，小屏上放不下，面板可以上下滚动（complete-reader-settings 设计 D5）。
void showReaderSettings(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _SettingsSheet());

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            _SettingSlider(
              label: '字号',
              valueText: '${settings.fontSize.round()}',
              value: settings.fontSize,
              min: ReaderSettings.minFontSize,
              max: ReaderSettings.maxFontSize,
              step: 1,
              onChanged: (value) => notifier.update(settings.copyWith(fontSize: value)),
            ),
            _SettingSlider(
              label: '行距',
              valueText: settings.lineHeight.toStringAsFixed(1),
              value: settings.lineHeight,
              min: ReaderSettings.minLineHeight,
              max: ReaderSettings.maxLineHeight,
              step: 0.1,
              onChanged: (value) => notifier.update(settings.copyWith(lineHeight: value)),
            ),
            _SettingSlider(
              label: '段距',
              valueText: settings.paragraphSpacing.toStringAsFixed(1),
              value: settings.paragraphSpacing,
              min: ReaderSettings.minParagraphSpacing,
              max: ReaderSettings.maxParagraphSpacing,
              step: 0.1,
              onChanged: (value) => notifier.update(settings.copyWith(paragraphSpacing: value)),
            ),
            _SettingSlider(
              label: '缩进',
              valueText: '${settings.indent} 字',
              value: settings.indent.toDouble(),
              min: ReaderSettings.minIndent.toDouble(),
              max: ReaderSettings.maxIndent.toDouble(),
              step: 1,
              onChanged: (value) => notifier.update(settings.copyWith(indent: value.round())),
            ),
            _SettingSlider(
              label: '边距',
              valueText: '${settings.margin.round()}',
              value: settings.margin,
              min: ReaderSettings.minMargin,
              max: ReaderSettings.maxMargin,
              step: 4,
              onChanged: (value) => notifier.update(settings.copyWith(margin: value)),
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
            SwitchListTile(
              title: const Text('屏幕常亮'),
              value: settings.keepScreenOn,
              onChanged: (value) => notifier.update(settings.copyWith(keepScreenOn: value)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置面板里的一行数值：左边是名字和当前值，右边是按 [step] 取整的滑块。[min]、[max] 都是 [step] 的整数倍。
class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 72, child: Text('$label $valueText')),
      Expanded(
        child: Slider(
          label: label,
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          // 取整到步长的整数倍。除以 1 / step 而不是乘以 step：18 * 0.1 是 1.8000000000000003，18 / 10 是 1.8
          onChanged: (value) => onChanged((value / step).round() / (1 / step)),
        ),
      ),
    ],
  );
}
