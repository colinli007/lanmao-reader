import 'package:flutter/material.dart';

import 'bookshelf/bookshelf_page.dart';
import 'settings/settings_page.dart';
import 'ui/icons.dart';
import 'ui/tokens.dart';

enum _Tab { shelf, settings }

/// 外壳（app-shell「底部 tab」，设计 D1）：底部书架、设置两个 tab。
///
/// - 书架常驻（`Offstage`），切走再切回时滚动位置和进行中的更新目录都还在。
/// - 设置页只在选中时构建：正文缓存的统计跟着页面重建，每次切过去重新统计。
///
/// 其它页面 push 到根导航器，盖住底部 tab。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Tab _tab = _Tab.shelf;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget item(_Tab tab, IconData icon, String label) {
      final color = tab == _tab ? colors.accent : colors.textSecondary;
      return Expanded(
        child: Tooltip(
          message: label,
          child: Semantics(
            selected: tab == _tab,
            child: InkWell(
              onTap: () => setState(() => _tab = tab),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 2,
                children: [
                  Icon(icon, color: color, size: 22),
                  Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: tab == _tab ? FontWeight.w600 : null)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Offstage(
            offstage: _tab != _Tab.shelf,
            child: TickerMode(enabled: _tab == _Tab.shelf, child: const BookshelfPage()),
          ),
          if (_tab == _Tab.settings) const SettingsPage(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border(top: BorderSide(color: colors.fill)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                item(_Tab.shelf, LucideIcons.libraryBig, '书架'),
                item(_Tab.settings, LucideIcons.settings, '设置'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
