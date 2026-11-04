import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// tab 页面（书架、设置）的顶栏：左边大号标题，右边少量图标按钮。
AppBar largeTitleAppBar(BuildContext context, {required String title, List<Widget> actions = const [], Color? backgroundColor}) => AppBar(
  toolbarHeight: 64,
  centerTitle: false,
  titleSpacing: AppSpacing.page,
  backgroundColor: backgroundColor,
  title: Text(title, style: Theme.of(context).textTheme.titleLarge),
  actions: [...actions, const SizedBox(width: AppSpacing.page - 8)],
);

/// 设置页这类页面的一组：圆角卡片，组内不加分割线（设计 D7）。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
    child: Material(
      color: AppColors.of(context).background,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// 选项单的一项。[danger] 为真时用危险色，比如移出书架。
typedef ActionSheetItem<T> = ({T value, String label, bool danger});

/// 从底部弹出的选项单：可选的说明文字、几个选项、和选项隔开的「取消」。点「取消」或点外面返回 null。
Future<T?> showActionSheet<T>(BuildContext context, {String? message, required List<ActionSheetItem<T>> items}) {
  final colors = AppColors.of(context);
  final textTheme = Theme.of(context).textTheme;
  Widget option(String label, Color color, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 56,
      child: Center(child: Text(label, style: textTheme.bodyLarge?.copyWith(color: color))),
    ),
  );
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.page, AppSpacing.page, AppSpacing.item),
              child: Text(message, style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            ),
          for (final item in items)
            option(item.label, item.danger ? colors.danger : colors.textPrimary, () => Navigator.pop(context, item.value)),
          Container(height: 8, color: colors.fill),
          option('取消', colors.textPrimary, () => Navigator.pop(context)),
        ],
      ),
    ),
  );
}

/// 居中的弹框：标题居中，说明是灰字，下面可以放 [content]（输入框、跳过的条目），底部是等宽的胶囊按钮。
/// 项目里的确认、提示、输入弹框都用它，样式统一在这里。
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, this.message, this.content, required this.actions});

  final String title;
  final String? message;
  final Widget? content;

  /// 从左到右排开、等宽，一般是「取消」（[FillButton]）和确认（[FilledButton]）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final message = this.message;
    final content = this.content;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.item),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, height: 1.5)),
            ],
            if (content != null) ...[const SizedBox(height: 16), content],
            const SizedBox(height: AppSpacing.section),
            Row(spacing: AppSpacing.item, children: [for (final action in actions) Expanded(child: action)]),
          ],
        ),
      ),
    );
  }
}

/// 确认弹框：「取消」和 [confirmLabel]，确认时返回 true，取消或点外面返回 false。
/// [danger] 为真时确认按钮用危险色（删除、移出、清除）；[confirmEnabled] 为假时确认按钮不可用（导入预览里没有可导入的内容）。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  required String confirmLabel,
  bool danger = false,
  bool confirmEnabled = true,
}) async {
  final colors = AppColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      message: message,
      content: content,
      actions: [
        FillButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: colors.onAccent) : null,
          onPressed: confirmEnabled ? () => Navigator.pop(context, true) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 导入预览里跳过的条目：浅灰底上一行一条，太多时可以滚动。
class SkippedList extends StatelessWidget {
  const SkippedList(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(AppSpacing.item),
      decoration: BoxDecoration(color: colors.fill, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [for (final line in lines) Text(line, style: TextStyle(color: colors.textSecondary, fontSize: 13))],
        ),
      ),
    );
  }
}

/// 输入一段文字的对话框：确定时返回输入的文字，取消时为 null。[initial] 是输入框里预先填好的内容。
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  required String hint,
  int maxLines = 1,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _InputDialog(title: title, hint: hint, maxLines: maxLines, initial: initial),
);

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.hint, required this.maxLines, required this.initial});

  final String title;
  final String hint;
  final int maxLines;
  final String initial;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.title,
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: widget.maxLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      FillButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('确定')),
    ],
  );
}

/// 提示弹框：只有一个「知道了」。
Future<void> showMessageDialog(BuildContext context, {required String title, required String message}) => showDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    title: title,
    message: message,
    actions: [FillButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
  ),
);

/// 浅灰底的胶囊按钮，用作次要操作（详情页的「加入书架」）。主要操作用 [FilledButton]。
class FillButton extends StatelessWidget {
  const FillButton({super.key, required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: colors.fill, foregroundColor: colors.textPrimary),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// 「− 值 +」步进器（设计 D6）：每次加减 [step]，到 [min]、[max] 时对应的按钮不可用。
/// 按钮的 tooltip 是「减小{label}」「增大{label}」。
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.label,
    required this.value,
    required this.valueText,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String valueText;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget button(IconData icon, String tooltip, double? target) => IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: colors.fill,
        disabledBackgroundColor: colors.fill,
        fixedSize: const Size(56, 36),
        shape: const StadiumBorder(),
      ),
      icon: Icon(icon, size: 18),
      onPressed: target == null ? null : () => onChanged(target),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(LucideIcons.minus, '减小$label', value - step >= min ? value - step : null),
        SizedBox(width: 48, child: Text(valueText, textAlign: TextAlign.center)),
        button(LucideIcons.plus, '增大$label', value + step <= max ? value + step : null),
      ],
    );
  }
}

/// 预设选择的一项：[child] 画在胶囊里，[color] 不为空时是胶囊的底色（主题色块），[label] 给读屏和测试用。
typedef PresetOption<T> = ({T value, String label, Widget child, Color? color});

/// 一排等宽的胶囊，选中的那个加描边（设计 D6）。[selected] 为空表示没有选中项，比如改版前存下的非预设行距。
class PresetPicker<T> extends StatelessWidget {
  const PresetPicker({super.key, required this.options, required this.selected, required this.onSelected});

  final List<PresetOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      spacing: AppSpacing.item,
      children: [
        for (final option in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: option.value == selected,
              label: option.label,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onSelected(option.value),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: option.color ?? colors.background,
                    shape: StadiumBorder(
                      side: option.value == selected
                          ? BorderSide(color: colors.textPrimary, width: 1.5)
                          : BorderSide(color: colors.fill, width: 1.5),
                    ),
                  ),
                  child: option.child,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
