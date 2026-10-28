import 'dart:ui';

import 'package:flutter/material.dart';

import 'cinema.dart';

/// 设计稿里有、代码里还没做的功能：点击时提示（设计 D4，清单见 proposal「暂未开发的功能」）。
void showNotDeveloped(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$feature暂未开发'), duration: const Duration(seconds: 2)));
}

/// 组件库「Icon Button / 玻璃」：半透明圆形按钮，背后模糊。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 18,
    this.blur = true,
    this.color = Night.glass,
    this.iconColor = Night.text,
  });

  final IconData icon;

  /// 为空时不加提示：按钮包在别的带提示的控件里（如 [PopupMenuButton]）。
  final String? tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool blur;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
    if (blur) {
      button = ClipOval(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: button),
      );
    }
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// 组件库「Button / 主要」「Button / 次要」：胶囊按钮，主要是米白底黑字，次要是半透明底白字。
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.height = 50,
    this.iconSize = 18,
    this.fontSize,
    this.padding = 24,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final double height;
  final double iconSize;
  final double? fontSize;

  /// 左右内边距：两个按钮并排、屏幕又窄时调小，文字才放得下。
  final double padding;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Night.bg : Night.text;
    return Material(
      color: primary ? Night.text : Night.glass,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                if (icon != null) Icon(icon, size: iconSize, color: foreground),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(fontSize ?? (primary ? 16 : 15), color: foreground, weight: primary ? FontWeight.w700 : FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 组件库「Chip」：筛选胶囊，选中时米白底。[danger] 是书源页的「失效」。
class CinemaChip extends StatelessWidget {
  const CinemaChip({super.key, required this.label, this.count, this.selected = false, this.danger = false, required this.onTap});

  final String label;
  final int? count;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Material(
      color: selected ? Night.text : Night.surface,
      shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: danger ? const Color(0x4DE8806A) : Night.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(
                label,
                style: sans(
                  13,
                  color: selected ? Night.bg : (danger ? Night.bad : Night.text2),
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null) Text('$count', style: sans(12, color: selected ? const Color(0x990C0C0E) : Night.text3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 组件库「Section Head」：左边标题和说明，右边链接。
class SectionHead extends StatelessWidget {
  const SectionHead({super.key, required this.title, this.meta, required this.link, required this.onLink});

  final String title;
  final String? meta;
  final String link;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(title, style: sans(19, weight: FontWeight.w800)),
      const SizedBox(width: 8),
      if (meta case final meta?)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: Night.text3),
            ),
          ),
        )
      else
        const Spacer(),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onLink,
        child: Row(
          spacing: 2,
          children: [
            Text(link, style: sans(13, color: Night.text2)),
            const Icon(Icons.chevron_right, size: 16, color: Night.text2),
          ],
        ),
      ),
    ],
  );
}

/// 组件库「Quick Action」：图标在上、文字在下。
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap, this.color, this.labelColor});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 图标颜色，默认 [Night.text]；[labelColor] 默认 [Night.text2]。「已在书架」两者都是琥珀色。
  final Color? color;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(icon, size: 20, color: color ?? Night.text),
          Text(label, maxLines: 1, style: sans(11, color: labelColor ?? Night.text2)),
        ],
      ),
    ),
  );
}

/// 组件库「Progress / 细线」。
class ThinProgress extends StatelessWidget {
  const ThinProgress({super.key, required this.value, this.height = 3, this.track = Night.glass, this.color = Night.amber});

  final double value;
  final double height;
  final Color track;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

/// 组件库「Tag」：描边小胶囊。
class OutlineTag extends StatelessWidget {
  const OutlineTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: ShapeDecoration(
      shape: StadiumBorder(side: const BorderSide(color: Night.line)),
    ),
    child: Align(
      widthFactor: 1,
      child: Text(label, style: sans(12, color: Night.text2)),
    ),
  );
}

/// 琥珀色小标签：目录里的「读到这里」、最新章节的「NEW」。
class AmberTag extends StatelessWidget {
  const AmberTag(this.label, {super.key, this.height = 22, this.letterSpacing, this.weight = FontWeight.w700});

  final String label;
  final double height;
  final double? letterSpacing;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: EdgeInsets.symmetric(horizontal: height == 22 ? 9 : 8),
    decoration: BoxDecoration(color: const Color(0x2EF0B357), borderRadius: BorderRadius.circular(height / 2)),
    child: Align(
      widthFactor: 1,
      child: Text(
        label,
        style: sans(10, color: Night.amber, weight: weight, letterSpacing: letterSpacing),
      ),
    ),
  );
}

/// 状态栏后面的渐变：页面滚上去以后，内容不和状态栏的时间、电量叠在一起。
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key});

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    height: MediaQuery.paddingOf(context).top + 12,
    child: const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.7, 1],
            colors: [Color(0xE60C0C0E), Color(0xB30C0C0E), Color(0x000C0C0E)],
          ),
        ),
      ),
    ),
  );
}
