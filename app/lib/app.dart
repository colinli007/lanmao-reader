import 'package:flutter/material.dart';

import 'app_info.dart';
import 'app_shell.dart';
import 'ui/theme.dart';

/// 极简主题（redesign-minimal-ui 设计 D2），跟随系统亮暗。
class LanmaoReaderApp extends StatelessWidget {
  const LanmaoReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: const AppShell(),
    );
  }
}
