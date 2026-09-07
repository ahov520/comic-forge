import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_explore_screens.dart';
import 'source_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _visited = <int>{0};

  void _selectTab(int index) {
    if (_tab == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = index;
      _visited.add(index);
    });
  }

  Widget _screen(int index) => switch (index) {
    0 => ShelfScreen(state: widget.state, onExplore: () => _selectTab(1)),
    1 => ExploreScreen(state: widget.state),
    2 => SearchScreen(state: widget.state),
    3 => SourceScreen(state: widget.state),
    _ => SettingsScreen(state: widget.state),
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < 5; i++)
              TickerMode(
                enabled: _tab == i,
                child: ExcludeFocus(
                  excluding: _tab != i,
                  // 首次点开再创建，返回时保留输入、筛选与滚动位置。
                  child: _visited.contains(i)
                      ? _screen(i)
                      : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.collections_bookmark_outlined),
                label: '书架',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                label: '探索',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
              NavigationDestination(
                icon: Icon(Icons.source_outlined),
                label: '源',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
