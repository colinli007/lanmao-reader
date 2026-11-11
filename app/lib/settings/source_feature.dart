import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../reader/reader_settings.dart';

/// 书源功能是否打开：其它平台一直打开；iOS 上默认关闭，在关于页连点版本号 [unlockTaps] 次后打开。
/// 打开后存进数据库，覆盖安装新版本时数据库保留，不用再点。
final class SourceFeatureNotifier extends Notifier<bool> {
  static const unlockTaps = 10;
  /// 设置表里的键，值为 `true` 表示已打开。
  static const unlockedKey = 'sourceFeature.unlocked';

  @override
  bool build() => defaultTargetPlatform != TargetPlatform.iOS || ref.read(initialSettingsProvider)[unlockedKey] == 'true';

  void unlock() {
    state = true;
    ref.read(databaseProvider).putSetting(unlockedKey, 'true');
  }
}

/// 关闭时隐藏所有在线入口：发现 tab、书架上的搜索、设置里的书源和替换净化规则。
final sourceFeatureProvider = NotifierProvider<SourceFeatureNotifier, bool>(SourceFeatureNotifier.new);
