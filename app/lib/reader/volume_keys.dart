import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 音量键翻页（reader「音量键翻页」，complete-reader-settings 设计 D3）：Android 上设置打开、菜单隐藏时，
/// 音量减往后、音量加往前，按下时调用一次 [turn]；重复和抬起也消费掉，按住不连续翻，系统也收不到这次按键。
/// 其它情况交回系统调音量。
KeyEventResult handleVolumeKey(KeyEvent event, {required bool enabled, required bool menu, required void Function(bool forward) turn}) {
  final forward = switch (event.logicalKey) {
    LogicalKeyboardKey.audioVolumeDown => true,
    LogicalKeyboardKey.audioVolumeUp => false,
    _ => null,
  };
  if (forward == null || !enabled || menu || defaultTargetPlatform != TargetPlatform.android) return KeyEventResult.ignored;
  if (event is KeyDownEvent) turn(forward);
  return KeyEventResult.handled;
}
