import 'package:flutter/material.dart';

/// 界面的配色（redesign-minimal-ui 设计 D2）：只有一个强调色，取自应用图标的底色；
/// 卡片、次要按钮、输入框用浅灰填充，不用阴影和描边。页面里一律通过 [AppColors.of] 取色。
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.fill,
    required this.groupedBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.danger,
  });

  /// 对比度按 WCAG AA 核对过：强调色在白底上 7.49，次要文字在白底上 4.54。
  static const light = AppColors(
    accent: Color(0xFF2F5D50),
    onAccent: Color(0xFFFFFFFF),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    fill: Color(0xFFF5F5F5),
    groupedBackground: Color(0xFFF5F5F5),
    textPrimary: Color(0xFF1F1F1F),
    textSecondary: Color(0xFF767676),
    danger: Color(0xFFD93025),
  );

  /// 图标底色放在深色背景上太暗，换成调亮的同色系：在 #121212 上对比度 9.08。
  /// 次要文字在最亮的 [fill] 上也有 5.1。
  static const dark = AppColors(
    accent: Color(0xFF8CBFAE),
    onAccent: Color(0xFF121212),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    fill: Color(0xFF2A2A2A),
    groupedBackground: Color(0xFF000000),
    textPrimary: Color(0xFFE6E6E6),
    textSecondary: Color(0xFF9A9A9A),
    danger: Color(0xFFF28B82),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  /// 主按钮、选中态、开关、tab。
  final Color accent;

  /// 强调色上面的文字和图标。
  final Color onAccent;

  /// 页面底色。
  final Color background;

  /// 浮在页面上的弹框、底部弹层、弹出菜单的底色。深色下比页面亮一档，盖上遮罩以后才看得出边界。
  final Color surface;

  /// 卡片、次要按钮、输入框。
  final Color fill;

  /// 设置页这类分组卡片页面的底色，卡片用 [background]。
  final Color groupedBackground;

  final Color textPrimary;

  /// 状态、说明。
  final Color textSecondary;

  /// 「更新失败」、移出书架这类出错和危险操作。
  final Color danger;

  @override
  AppColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? fill,
    Color? groupedBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? danger,
  }) => AppColors(
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    fill: fill ?? this.fill,
    groupedBackground: groupedBackground ?? this.groupedBackground,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    danger: danger ?? this.danger,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      groupedBackground: Color.lerp(groupedBackground, other.groupedBackground, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// 间距。
abstract final class AppSpacing {
  /// 页面内容离屏幕左右两边的距离。
  static const page = 20.0;

  /// 分组卡片之间、区块之间。
  static const section = 24.0;

  /// 同一区块里相邻元素之间。
  static const item = 12.0;
}

/// 圆角。
abstract final class AppRadius {
  static const card = 12.0;
  static const sheet = 16.0;
}
