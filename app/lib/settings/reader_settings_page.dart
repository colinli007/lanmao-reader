import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reader/reader_settings.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// 阅读设置页（settings「设置页入口」，redesign-minimal-ui 设计 D7）：设一次就不常动的两个开关，不放在阅读页里。
/// 和阅读页里改的字号、主题等是同一份阅读设置，改了立即生效并落盘。
class ReaderSettingsPage extends ConsumerWidget {
  const ReaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      appBar: AppBar(title: const Text('阅读设置'), backgroundColor: colors.groupedBackground),
      body: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.item),
        children: [
          SettingsGroup(
            children: [
              SwitchListTile(
                title: const Text('跟随系统深色'),
                subtitle: const Text('系统是深色模式时，阅读页用暗主题'),
                value: settings.followSystemDark,
                onChanged: (value) => notifier.update(settings.copyWith(followSystemDark: value)),
              ),
              SwitchListTile(
                title: const Text('屏幕常亮'),
                subtitle: const Text('阅读时屏幕不自动熄灭'),
                value: settings.keepScreenOn,
                onChanged: (value) => notifier.update(settings.copyWith(keepScreenOn: value)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
