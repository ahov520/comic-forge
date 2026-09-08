import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/shelf_update_notices.dart';
import '../state/shelf_update_scheduler.dart';
import 'book_detail_screen.dart';
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
  late ShelfUpdateScheduler _shelfUpdateScheduler;
  int _tab = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    _shelfUpdateScheduler = ShelfUpdateScheduler(widget.state);
    _bindNotifier(widget.state);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLaunchRequest());
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.updateNotifier.setOnOpen(null);
      _shelfUpdateScheduler.dispose();
      _shelfUpdateScheduler = ShelfUpdateScheduler(widget.state);
      _bindNotifier(widget.state);
      _openLaunchRequest();
    }
  }

  @override
  void dispose() {
    widget.state.updateNotifier.setOnOpen(null);
    _shelfUpdateScheduler.dispose();
    super.dispose();
  }

  void _bindNotifier(AppState state) {
    state.updateNotifier.setOnOpen(_onOpenRequest);
  }

  void _openLaunchRequest() {
    if (!mounted) return;
    final launch = widget.state.updateNotifier.takeLaunchRequest();
    if (launch != null) _onOpenRequest(launch);
  }

  void _onOpenRequest(ShelfUpdateOpenRequest request) {
    final book = widget.state.shelfBookFor(
      bookUrl: request.bookUrl,
      sourceId: request.sourceId,
    );
    if (book == null || !mounted) return;
    _selectTab(0);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(book: book, appState: widget.state),
      ),
    );
  }

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
        // 搜索页的输入框在正文中，其它表单由弹窗或独立页面避让键盘。
        resizeToAvoidBottomInset: _tab == 2,
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
