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

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        body: switch (_tab) {
          0 => ShelfScreen(state: s),
          1 => ExploreScreen(state: s),
          2 => SearchScreen(state: s),
          3 => SourceScreen(state: s),
          _ => SettingsScreen(state: s),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), label: '书架'),
            NavigationDestination(icon: Icon(Icons.explore_outlined), label: '探索'),
            NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
            NavigationDestination(icon: Icon(Icons.source_outlined), label: '源'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
          ],
        ),
      ),
    );
  }
}
