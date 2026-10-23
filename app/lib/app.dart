import 'package:flutter/material.dart';

import 'app_info.dart';
import 'bookshelf/bookshelf_page.dart';

/// Material 3 默认组件和主题，跟随系统亮暗。
class NovelReaderApp extends StatelessWidget {
  const NovelReaderApp({super.key});

  static const _seed = Colors.teal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(colorSchemeSeed: _seed),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      home: const BookshelfPage(),
    );
  }
}
