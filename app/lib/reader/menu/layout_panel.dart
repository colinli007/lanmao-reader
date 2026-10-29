import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import '../reader_settings.dart';

/// 排版面板（reader「阅读设置」，redesign-minimal-ui 设计 D5、D6）：字号、缩进、边距用步进，行距、段距用三个预设，翻页方式四选一。
class LayoutPanel extends ConsumerWidget {
  const LayoutPanel({super.key});

  static const _presetNames = ['紧凑', '适中', '宽松'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final colors = AppColors.of(context);

    Widget row(String label, Widget control, {bool expand = false}) => SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label)),
          if (expand) Expanded(child: control) else ...[const Spacer(), control],
        ],
      ),
    );

    /// 行距、段距的三个预设；图标是三条横线，预设越宽松线越疏。
    List<PresetOption<double>> presets(String name, List<double> values) => [
      for (final (i, value) in values.indexed)
        (
          value: value,
          label: '${_presetNames[i]}$name',
          color: null,
          child: CustomPaint(size: const Size(18, 16), painter: _Lines(gap: 3.0 + i * 2, color: colors.textPrimary)),
        ),
    ];

    final lineHeight = settings.lineHeight;
    final paragraphSpacing = settings.paragraphSpacing;
    return ConstrainedBox(
      // 横屏等矮屏幕上放不下时可以滚动
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.item, AppSpacing.page, 0),
        child: Column(
          children: [
            row(
              '字号',
              ValueStepper(
                label: '字号',
                value: settings.fontSize,
                valueText: '${settings.fontSize.round()}',
                min: ReaderSettings.minFontSize,
                max: ReaderSettings.maxFontSize,
                step: 1,
                onChanged: (value) => notifier.update(settings.copyWith(fontSize: value)),
              ),
            ),
            row(
              '行距',
              PresetPicker<double>(
                options: presets('行距', ReaderSettings.lineHeightPresets),
                selected: ReaderSettings.lineHeightPresets.contains(lineHeight) ? lineHeight : null,
                onSelected: (value) => notifier.update(settings.copyWith(lineHeight: value)),
              ),
              expand: true,
            ),
            row(
              '段距',
              PresetPicker<double>(
                options: presets('段距', ReaderSettings.paragraphSpacingPresets),
                selected: ReaderSettings.paragraphSpacingPresets.contains(paragraphSpacing) ? paragraphSpacing : null,
                onSelected: (value) => notifier.update(settings.copyWith(paragraphSpacing: value)),
              ),
              expand: true,
            ),
            row(
              '缩进',
              ValueStepper(
                label: '缩进',
                value: settings.indent.toDouble(),
                valueText: '${settings.indent} 字',
                min: ReaderSettings.minIndent.toDouble(),
                max: ReaderSettings.maxIndent.toDouble(),
                step: 1,
                onChanged: (value) => notifier.update(settings.copyWith(indent: value.round())),
              ),
            ),
            row(
              '边距',
              ValueStepper(
                label: '边距',
                value: settings.margin,
                valueText: '${settings.margin.round()}',
                min: ReaderSettings.minMargin,
                max: ReaderSettings.maxMargin,
                step: 4,
                onChanged: (value) => notifier.update(settings.copyWith(margin: value)),
              ),
            ),
            row(
              '翻页',
              PresetPicker<PageMode>(
                options: [
                  for (final mode in PageMode.values)
                    (value: mode, label: mode.label, color: null, child: Text(mode.label, style: const TextStyle(fontSize: 13))),
                ],
                selected: settings.pageMode,
                onSelected: (mode) => notifier.update(settings.copyWith(pageMode: mode)),
              ),
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 三条等长横线，[gap] 是线之间的距离。
class _Lines extends CustomPainter {
  const _Lines({required this.gap, required this.color});

  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final top = (size.height - gap * 2) / 2;
    for (var i = 0; i < 3; i++) {
      final y = top + gap * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Lines old) => old.gap != gap || old.color != color;
}
