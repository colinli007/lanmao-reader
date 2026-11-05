import 'package:flutter/widgets.dart';

/// lucide 图标（https://lucide.dev ，ISC 许可证，见 assets/fonts/LUCIDE_LICENSE.txt）。
/// 只打包 lucide.ttf 一个字体文件，release 构建时按用到的图标裁剪；名字和 lucide 的图标名一致（驼峰）。
/// 要用新图标时，按 lucide.ttf 里的码位加一个常量。
abstract final class LucideIcons {
  static const aLargeSmall = IconData(0xe587, fontFamily: 'Lucide');
  static const arrowDownUp = IconData(0xe046, fontFamily: 'Lucide');
  static const arrowLeftRight = IconData(0xe24a, fontFamily: 'Lucide');
  static const ban = IconData(0xe051, fontFamily: 'Lucide');
  static const check = IconData(0xe06c, fontFamily: 'Lucide');
  static const checkCircle2 = IconData(0xe226, fontFamily: 'Lucide');
  static const chevronDown = IconData(0xe06d, fontFamily: 'Lucide');
  static const chevronLeft = IconData(0xe06e, fontFamily: 'Lucide');
  static const chevronRight = IconData(0xe06f, fontFamily: 'Lucide');
  static const compass = IconData(0xe09b, fontFamily: 'Lucide');
  static const copy = IconData(0xe09e, fontFamily: 'Lucide');
  static const ellipsisVertical = IconData(0xe0b7, fontFamily: 'Lucide');
  static const filePlus = IconData(0xe0c9, fontFamily: 'Lucide');
  static const gitCommitHorizontal = IconData(0xe0e3, fontFamily: 'Lucide');
  static const libraryBig = IconData(0xe54e, fontFamily: 'Lucide');
  static const list = IconData(0xe106, fontFamily: 'Lucide');
  static const listChecks = IconData(0xe1d0, fontFamily: 'Lucide');
  static const locateFixed = IconData(0xe1db, fontFamily: 'Lucide');
  static const minus = IconData(0xe11c, fontFamily: 'Lucide');
  static const moon = IconData(0xe11e, fontFamily: 'Lucide');
  static const palette = IconData(0xe1dd, fontFamily: 'Lucide');
  static const pencil = IconData(0xe1f9, fontFamily: 'Lucide');
  static const plus = IconData(0xe13d, fontFamily: 'Lucide');
  static const refreshCw = IconData(0xe145, fontFamily: 'Lucide');
  static const scrollText = IconData(0xe45f, fontFamily: 'Lucide');
  static const search = IconData(0xe151, fontFamily: 'Lucide');
  static const settings = IconData(0xe154, fontFamily: 'Lucide');
  static const share = IconData(0xe155, fontFamily: 'Lucide');
  static const sun = IconData(0xe178, fontFamily: 'Lucide');
  static const trash2 = IconData(0xe18e, fontFamily: 'Lucide');
  static const x = IconData(0xe1b2, fontFamily: 'Lucide');
}
