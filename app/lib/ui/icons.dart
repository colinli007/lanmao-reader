import 'package:flutter/widgets.dart';

/// 设计稿用的 lucide 图标（https://lucide.dev ，ISC 许可证，见 assets/fonts/LUCIDE_LICENSE.txt）。
/// 只打包 lucide.ttf 一个字体文件，release 构建时按用到的图标裁剪；名字和 lucide 的图标名一致（驼峰）。
/// 要用新图标时，按 lucide.ttf 里的码位加一个常量。
abstract final class LucideIcons {
  static const arrowDownUp = IconData(0xe046, fontFamily: 'Lucide');
  static const audioLines = IconData(0xe55a, fontFamily: 'Lucide');
  static const ban = IconData(0xe051, fontFamily: 'Lucide');
  static const bookmark = IconData(0xe060, fontFamily: 'Lucide');
  static const check = IconData(0xe06c, fontFamily: 'Lucide');
  static const chevronLeft = IconData(0xe06e, fontFamily: 'Lucide');
  static const chevronRight = IconData(0xe06f, fontFamily: 'Lucide');
  static const circleCheck = IconData(0xe226, fontFamily: 'Lucide');
  static const cloudDownload = IconData(0xe089, fontFamily: 'Lucide');
  static const compass = IconData(0xe09b, fontFamily: 'Lucide');
  static const download = IconData(0xe0b2, fontFamily: 'Lucide');
  static const ellipsis = IconData(0xe0b6, fontFamily: 'Lucide');
  static const hardDrive = IconData(0xe0ed, fontFamily: 'Lucide');
  static const headphones = IconData(0xe0f1, fontFamily: 'Lucide');
  static const info = IconData(0xe0f9, fontFamily: 'Lucide');
  static const layers = IconData(0xe529, fontFamily: 'Lucide');
  static const libraryBig = IconData(0xe54e, fontFamily: 'Lucide');
  static const list = IconData(0xe106, fontFamily: 'Lucide');
  static const listChecks = IconData(0xe1d0, fontFamily: 'Lucide');
  static const locateFixed = IconData(0xe1db, fontFamily: 'Lucide');
  static const moon = IconData(0xe11e, fontFamily: 'Lucide');
  static const play = IconData(0xe13c, fontFamily: 'Lucide');
  static const plus = IconData(0xe13d, fontFamily: 'Lucide');
  static const refreshCw = IconData(0xe145, fontFamily: 'Lucide');
  static const repeat = IconData(0xe146, fontFamily: 'Lucide');
  static const rotateCw = IconData(0xe149, fontFamily: 'Lucide');
  static const scrollText = IconData(0xe45f, fontFamily: 'Lucide');
  static const search = IconData(0xe151, fontFamily: 'Lucide');
  static const settings2 = IconData(0xe245, fontFamily: 'Lucide');
  static const share = IconData(0xe155, fontFamily: 'Lucide');
  static const shieldCheck = IconData(0xe1ff, fontFamily: 'Lucide');
  static const skipBack = IconData(0xe15f, fontFamily: 'Lucide');
  static const skipForward = IconData(0xe160, fontFamily: 'Lucide');
  static const sun = IconData(0xe178, fontFamily: 'Lucide');
  static const trash2 = IconData(0xe18e, fontFamily: 'Lucide');
  static const type = IconData(0xe198, fontFamily: 'Lucide');
  static const userRound = IconData(0xe468, fontFamily: 'Lucide');
  static const wandSparkles = IconData(0xe357, fontFamily: 'Lucide');
  static const x = IconData(0xe1b2, fontFamily: 'Lucide');
}
