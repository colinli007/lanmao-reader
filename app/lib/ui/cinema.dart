import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 「影院」设计稿（`untitled.pen`）的颜色令牌，名字和设计稿里的变量一致。
abstract final class Night {
  static const bg = Color(0xFF0C0C0E);
  static const surface = Color(0xFF17171A);
  static const elevated = Color(0xFF232327);
  static const glass = Color(0x1FFFFFFF);
  static const line = Color(0x14FFFFFF);
  static const text = Color(0xFFF4F2EE);
  static const text2 = Color(0xFFA9A6A0);
  static const text3 = Color(0xFF6F6C67);
  static const amber = Color(0xFFF0B357);
  static const ok = Color(0xFF8CC6A0);
  static const bad = Color(0xFFE8806A);

  /// 目录里已读章节的序号和图标。
  static const dim = Color(0xFF4A4844);
}

/// 设计稿里的衬线标题（书名、章节序号、大数字）：打包的 Noto Serif SC Black 子集（设计 D2），
/// 子集里没有的生僻字由系统字体补上。只打包了 Black 一个字重。
TextStyle serif(double size, {Color color = Night.text, double? letterSpacing, double? height}) => TextStyle(
  fontFamily: 'NotoSerifSC',
  fontSize: size,
  fontWeight: FontWeight.w900,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// 设计稿里的无衬线字：Noto Sans SC，用系统默认字体。
TextStyle sans(double size, {Color color = Night.text, FontWeight weight = FontWeight.w400, double? letterSpacing, double? height}) =>
    TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height);

/// 外壳页面的深色主题（设计 D3）：不跟随系统亮暗，没有设计稿的页面也用它。
ThemeData cinemaTheme() {
  final scheme = const ColorScheme.dark(
    primary: Night.text,
    onPrimary: Night.bg,
    secondary: Night.amber,
    onSecondary: Night.bg,
    error: Night.bad,
    surface: Night.bg,
    onSurface: Night.text,
    onSurfaceVariant: Night.text2,
    surfaceContainerLowest: Night.bg,
    surfaceContainerLow: Night.surface,
    surfaceContainer: Night.surface,
    surfaceContainerHigh: Night.elevated,
    surfaceContainerHighest: Night.elevated,
    outline: Night.text3,
    outlineVariant: Night.line,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Night.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Night.bg,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    dividerTheme: const DividerThemeData(color: Night.line, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Night.elevated,
      contentTextStyle: sans(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Night.bg : Night.text2),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Night.text : Night.glass),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Night.amber,
      inactiveTrackColor: Night.glass,
      thumbColor: Night.text,
      overlayColor: Color(0x1FF0B357),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Night.amber, linearTrackColor: Night.glass),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Night.surface, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: Night.surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(color: Night.elevated, surfaceTintColor: Colors.transparent),
  );
}
