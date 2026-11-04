import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阅读页的屏幕亮度（reader「阅读页亮度」，add-reader-brightness 设计 D1、D2）。
/// 平台通道 `novel_reader/screen` 的 `brightness(double?)`：0.01 到 1 是亮度，null 是恢复成系统的亮度。
/// 记住上一次设的值，相同的不再调用；一开始是没有覆盖，和系统一样。不支持的平台上什么都不做。
class ScreenBrightness {
  static const _channel = MethodChannel('novel_reader/screen');

  /// 只有 Android 和 iOS 能改亮度，macOS 没有公开接口。
  static bool get supported => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  double? _value;

  void set(double? value) {
    if (!supported || value == _value) return;
    _value = value;
    apply(value);
  }

  /// 交给平台。测试里换成记录调用的实现。
  @protected
  void apply(double? value) => unawaited(_channel.invokeMethod<void>('brightness', value));
}

final screenBrightnessProvider = Provider<ScreenBrightness>((ref) => ScreenBrightness());
