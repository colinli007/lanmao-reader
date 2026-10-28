import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../bookshelf/bookshelf_page.dart';
import '../online/source_list_page.dart';
import '../settings/settings_page.dart';
import 'cinema.dart';
import 'icons.dart';
import 'widgets.dart';

/// 首页：书架、书源、我的三个页面和底部悬浮的 Tab（组件库「Tab Bar」）。「发现」还没做，点了只提示。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Tab {
  shelf('书架', LucideIcons.libraryBig),
  discover('发现', LucideIcons.compass),
  sources('书源', LucideIcons.layers),
  mine('我的', LucideIcons.userRound);

  const _Tab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _HomeShellState extends State<HomeShell> {
  _Tab _current = _Tab.shelf;

  static const _pages = [_Tab.shelf, _Tab.sources, _Tab.mine];

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    // 「我的」只在选中时构建：正文缓存进入时统计、离开就丢掉（add-settings 设计 D3）；书架和书源留着滚动位置和筛选
    body: Stack(
      children: [
        IndexedStack(
          index: _pages.indexOf(_current),
          children: [const BookshelfPage(), const SourceListPage(), if (_current == _Tab.mine) const SettingsPage() else const SizedBox()],
        ),
        const StatusBarScrim(),
      ],
    ),
    bottomNavigationBar: _TabBar(current: _current, onSelect: _select),
  );

  void _select(_Tab tab) {
    if (tab == _Tab.discover) return showNotDeveloped(context, '发现');
    setState(() => _current = tab);
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final _Tab current;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 28, 20, math.max(MediaQuery.paddingOf(context).bottom, 30)),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 12), blurRadius: 30)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xE61C1C20),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Night.line),
            ),
            child: Row(
              children: [
                for (final tab in _Tab.values)
                  Expanded(
                    child: _TabItem(tab: tab, selected: tab == current, onTap: () => onSelect(tab)),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.selected, required this.onTap});

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Night.text : Night.text3;
    return Tooltip(
      message: tab.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? Night.glass : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 3,
                children: [
                  Icon(tab.icon, size: 20, color: color),
                  Text(
                    tab.label,
                    style: sans(10, color: color, weight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
