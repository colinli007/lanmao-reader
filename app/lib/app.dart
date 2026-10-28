import 'package:flutter/material.dart';

import 'app_info.dart';
import 'ui/cinema.dart';
import 'ui/home_shell.dart';

/// 「影院」深色外壳（redesign-cinema-ui），不跟随系统亮暗；正文的颜色由阅读主题决定。
class NovelReaderApp extends StatelessWidget {
  const NovelReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: appName, theme: cinemaTheme(), home: const HomeShell());
  }
}
