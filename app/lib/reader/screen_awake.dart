import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阻止屏幕因为没有操作而自动熄灭（reader「屏幕常亮」，complete-reader-settings 设计 D4）。
/// 平台通道 `novel_reader/screen` 的 `keepOn(bool)`，三个平台的实现在各自的原生入口里。
/// 记住上一次设的值，相同的不再调用；一开始是没有常亮，和系统默认一样。
class ScreenAwake {
  static const _channel = MethodChannel('novel_reader/screen');

  bool _on = false;

  void set(bool on) {
    if (on == _on) return;
    _on = on;
    apply(on);
  }

  /// 交给平台。测试里换成记录调用的实现。
  @protected
  void apply(bool on) => unawaited(_channel.invokeMethod<void>('keepOn', on));
}

final screenAwakeProvider = Provider<ScreenAwake>((ref) => ScreenAwake());
