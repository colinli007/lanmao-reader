import 'package:flutter/material.dart';

import 'tokens.dart';

/// 由 [AppColors] 构造的主题（redesign-minimal-ui 设计 D2）。不用 `colorSchemeSeed`：
/// 它生成的配色带色调，卡片和背景都会染上强调色。Material 组件的阴影、描边和染色一律去掉。
ThemeData appTheme(Brightness brightness) {
  final colors = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    error: colors.danger,
    onError: colors.onAccent,
    surface: colors.background,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerLowest: colors.background,
    surfaceContainerLow: colors.background,
    surfaceContainer: colors.background,
    surfaceContainerHigh: colors.fill,
    surfaceContainerHighest: colors.fill,
    outline: colors.textSecondary,
    outlineVariant: colors.fill,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary);
  return base.copyWith(
    extensions: [colors],
    scaffoldBackgroundColor: colors.background,
    splashFactory: InkRipple.splashFactory,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: colors.textSecondary),
    ),
    iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: colors.fill, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      iconColor: colors.textSecondary,
      subtitleTextStyle: text.bodySmall?.copyWith(color: colors.textSecondary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(colors.background),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.accent : colors.textSecondary.withValues(alpha: 0.3),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: colors.accent)),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.textPrimary,
      contentTextStyle: TextStyle(color: colors.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent, linearTrackColor: colors.fill),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.fill,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: 0.12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.fill,
      hintStyle: TextStyle(color: colors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.fill,
      selectedColor: colors.accent,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
  );
}
