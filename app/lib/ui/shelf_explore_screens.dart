import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/shelf_sort.dart';
import 'book_detail_screen.dart';
import 'book_tile_typography.dart';
import 'comic_reading_stats_screen.dart';
import 'explore_results.dart';
import 'downloads_screen.dart';
import 'reading_history_screen.dart';
import 'shelf_groups_screen.dart';
import 'search_screen.dart';
import 'skeleton.dart';
import 'source_screen.dart';
import 'widgets.dart';

/// 书架。
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.state, required this.onExplore});
  final AppState state;
  final VoidCallback onExplore;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  // six-screens ①：340px 屏宽下约 92×118 的封面，标题另占一行。
  static const _coverAspectRatio = 92 / 118;

  /// 筛选：0=全部 1=连载中 2=已完结（按 book.kind 关键词，缺失归入全部）
  int _filter = 0;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _selected = <String>{};
  String _query = '';
  bool _selecting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String value) {
    final query = value.trim().toLowerCase();
    if (_query != query && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() => _query = query);
  }

  void _clearSearch() {
    _searchController.clear();
    _search('');
  }

  Future<void> _setSort(ShelfSort sort) async {
    FocusScope.of(context).unfocus();
    if (widget.state.shelfSort != sort && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await widget.state.setShelfSort(sort);
  }

  Future<void> _refreshUpdates() async {
    final result = await widget.state.refreshShelfUpdates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已检查 ${result.checked} 本'
          '${result.failed > 0 ? ' · ${result.failed} 本失败，可重试' : ''}'
          '${result.skipped > 0 ? ' · ${result.skipped} 本无可用源或已移除' : ''}',
        ),
      ),
    );
  }

  List<Book> _selectedBooks() => [
    for (final book in widget.state.shelf)
      if (_selected.contains(book.bookUrl)) book,
  ];

  void _enterSelection([Book? book]) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selecting = true;
      if (book != null) _selected.add(book.bookUrl);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (!_selected.remove(book.bookUrl)) _selected.add(book.bookUrl);
    });
  }

  void _toggleSelectVisible(List<Book> books) {
    setState(() {
      final urls = books.map((book) => book.bookUrl).toSet();
      if (urls.isNotEmpty && urls.every(_selected.contains)) {
        _selected.removeAll(urls);
      } else {
        _selected.addAll(urls);
      }
    });
  }

  Future<void> _batchGroups() async {
    final books = _selectedBooks();
    if (books.isEmpty) return;
    await showShelfGroupPickerFor(context, widget.state, books);
  }

  Future<void> _batchClearUpdates() async {
    final books = _selectedBooks();
    if (books.isEmpty) return;
    await widget.state.clearShelfUpdatesFor(books);
  }

  Future<void> _batchRemove() async {
    final books = _selectedBooks();
    if (books.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出书架'),
        content: Text('将选中的 ${books.length} 本漫画移出书架？阅读进度、历史和统计会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.state.removeShelfBooks(books);
    if (mounted) _exitSelection();
  }

  void _openStats(Book book) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ComicReadingStatsScreen(
          stats: widget.state.readingStats,
          sources: widget.state.sources,
          book: book,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = BookTileTypography.shelfTitle(context);
    final titleHeight = BookTileTypography.lineHeight(context, titleStyle);
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final books = widget.state.shelfBooks(
          query: _query,
          kindFilter: _filter,
        );
        final selectedBooks = _selectedBooks();
        final visibleUrls = books.map((book) => book.bookUrl).toSet();
        final allVisibleSelected =
            visibleUrls.isNotEmpty && visibleUrls.every(_selected.contains);
        final canClearUpdates = selectedBooks.any(
          (book) => widget.state.shelfUpdateFor(book) != null,
        );
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selecting) _exitSelection();
          },
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              notificationPredicate: (_) => !_selecting,
              onRefresh: _refreshUpdates,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: _selecting
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: '退出多选',
                                      onPressed: _exitSelection,
                                      icon: const Icon(Icons.close),
                                    ),
                                    Expanded(
                                      child: ScreenTitle(
                                        '已选 ${selectedBooks.length}',
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: allVisibleSelected
                                          ? '取消全选'
                                          : '全选',
                                      onPressed: books.isEmpty
                                          ? null
                                          : () => _toggleSelectVisible(books),
                                      icon: Icon(
                                        allVisibleSelected
                                            ? Icons.deselect
                                            : Icons.select_all,
                                      ),
                                    ),
                                  ],
                                ),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      TextButton(
                                        onPressed: selectedBooks.isEmpty
                                            ? null
                                            : _batchGroups,
                                        child: const Text('设置分组'),
                                      ),
                                      TextButton(
                                        onPressed: canClearUpdates
                                            ? _batchClearUpdates
                                            : null,
                                        child: const Text('清除更新角标'),
                                      ),
                                      TextButton(
                                        onPressed: selectedBooks.length == 1
                                            ? () => _openStats(
                                                selectedBooks.single,
                                              )
                                            : null,
                                        child: const Text('阅读统计'),
                                      ),
                                      TextButton(
                                        onPressed: selectedBooks.isEmpty
                                            ? null
                                            : _batchRemove,
                                        child: const Text('移出书架'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const Expanded(child: ScreenTitle('书架')),
                                IconButton(
                                  tooltip: '检查书架更新',
                                  onPressed:
                                      widget.state.checkingShelfUpdates ||
                                          widget.state.shelf.isEmpty
                                      ? null
                                      : _refreshUpdates,
                                  icon: widget.state.checkingShelfUpdates
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                                ),
                                PopupMenuButton<ShelfSort>(
                                  tooltip: '排序：${widget.state.shelfSort.label}',
                                  initialValue: widget.state.shelfSort,
                                  onSelected: _setSort,
                                  itemBuilder: (_) => [
                                    for (final sort in ShelfSort.values)
                                      PopupMenuItem(
                                        value: sort,
                                        child: Text(sort.label),
                                      ),
                                  ],
                                  icon: const Icon(Icons.sort),
                                ),
                                if (widget.state.shelf.isNotEmpty)
                                  IconButton(
                                    tooltip: '批量管理',
                                    onPressed: books.isEmpty
                                        ? null
                                        : _enterSelection,
                                    icon: const Icon(Icons.checklist),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: '书架操作',
                                  onSelected: (action) {
                                    if (action == 'select') {
                                      _enterSelection();
                                    } else if (action == 'groups') {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ShelfGroupsScreen(
                                            state: widget.state,
                                          ),
                                        ),
                                      );
                                    } else if (action == 'history') {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ReadingHistoryScreen(
                                            state: widget.state,
                                          ),
                                        ),
                                      );
                                    } else if (action == 'downloads') {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => DownloadsScreen(
                                            state: widget.state,
                                          ),
                                        ),
                                      );
                                    } else {
                                      widget.state.clearShelfUpdates();
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'select',
                                      enabled: books.isNotEmpty,
                                      child: const Text('批量管理'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'groups',
                                      child: Text('分组管理'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'history',
                                      child: Text('阅读历史'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'downloads',
                                      child: Text('下载管理'),
                                    ),
                                    PopupMenuItem(
                                      value: 'clear',
                                      enabled: widget.state.shelf.any(
                                        (b) =>
                                            widget.state.shelfUpdateFor(b) !=
                                            null,
                                      ),
                                      child: const Text('清除全部更新角标'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: '搜索书架',
                          hintText: '漫画名或作者',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearSearch,
                                ),
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: _search,
                      ),
                    ),
                  ),
                  if (widget.state.shelfGroups.groups.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(widget.state.shelfGroups.filter),
                          initialValue:
                              widget.state.shelfGroups.filter ?? 'all',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '书架分组',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('全部分组'),
                            ),
                            const DropdownMenuItem(
                              value: '',
                              child: Text('未分组'),
                            ),
                            for (final group in widget.state.shelfGroups.groups)
                              DropdownMenuItem(
                                value: group.id,
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) => widget.state.shelfGroups
                              .selectFilter(id == 'all' ? null : id),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: FilterChipRow(
                      children: ['全部', '连载中', '已完结']
                          .asMap()
                          .entries
                          .map(
                            (e) => FilterChoiceChip(
                              label: Text(
                                e.value,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: _filter == e.key,
                              onSelected: (_) =>
                                  setState(() => _filter = e.key),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (books.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: widget.state.shelf.isEmpty
                          ? EmptyStateView(
                              icon: Icons.collections_bookmark_outlined,
                              title: '书架还没有漫画',
                              message: '收藏喜欢的漫画，在这里继续上次的阅读。',
                              actionLabel: '去探索',
                              onAction: widget.onExplore,
                            )
                          : EmptyStateView(
                              icon: Icons.filter_list_outlined,
                              title: _query.isEmpty ? '这个分类还没有漫画' : '没有匹配的漫画',
                              message: _query.isEmpty
                                  ? '试试其他分类，或查看书架中的全部漫画。'
                                  : '当前分组与分类下未找到匹配漫画，试试其他漫画名或作者，或清空搜索。',
                              actionLabel: _query.isEmpty ? '查看全部' : '清空搜索',
                              onAction: () {
                                if (_query.isNotEmpty) {
                                  _clearSearch();
                                  return;
                                }
                                setState(() => _filter = 0);
                                widget.state.shelfGroups.selectFilter(null);
                              },
                            ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = math.max(
                            1,
                            (constraints.crossAxisExtent / (120 + 12)).ceil(),
                          );
                          final coverWidth =
                              (constraints.crossAxisExtent -
                                  12 * (columns - 1)) /
                              columns;
                          return SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent:
                                      coverWidth / _coverAspectRatio +
                                      6 +
                                      titleHeight,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final b = books[i];
                              final update = widget.state.shelfUpdateFor(b);
                              final prog = widget.state.progress[b.bookUrl];
                              final progLabel =
                                  prog == null || prog.chapterTitle.isEmpty
                                  ? ''
                                  : prog.chapterTitle;
                              return InkWell(
                                key: ValueKey('shelf-book-${b.bookUrl}'),
                                borderRadius: BorderRadius.circular(12),
                                onLongPress: () {
                                  if (_selecting) {
                                    setState(() => _selected.add(b.bookUrl));
                                  } else {
                                    _enterSelection(b);
                                  }
                                },
                                onTap: () {
                                  FocusScope.of(context).unfocus();
                                  if (_selecting) {
                                    _toggleSelected(b);
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookDetailScreen(
                                        book: b,
                                        appState: widget.state,
                                      ),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: _coverAspectRatio,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: BookCover(url: b.coverUrl),
                                            ),
                                            if (update != null)
                                              Positioned(
                                                top: 6,
                                                left: 6,
                                                right: 6,
                                                child: Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Tooltip(
                                                    message:
                                                        '${update.latestTitle}\n长按封面可批量管理',
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          update.label,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (progLabel.isNotEmpty)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 2,
                                                      ),
                                                  color: Colors.black54,
                                                  child: Text(
                                                    progLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (_selecting)
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: Icon(
                                                  _selected.contains(b.bookUrl)
                                                      ? Icons.check_circle
                                                      : Icons.circle_outlined,
                                                  color:
                                                      _selected.contains(
                                                        b.bookUrl,
                                                      )
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                      : Colors.white,
                                                  shadows: const [
                                                    Shadow(
                                                      color: Colors.black54,
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Tooltip(
                                      message: b.name,
                                      child: Text(
                                        b.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: titleStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }, childCount: books.length),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 探索：选源 → 发现入口。
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  ComicSource? _source;
  (String, String)? _entry;
  Future<Paged<Book>>? _future;
  int _entryGeneration = 0;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _syncSource();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      _source = null;
      _entry = null;
      _future = null;
      _entryGeneration++;
      _syncSource();
      widget.state.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() => setState(_syncSource);

  void _syncSource() {
    final enabled = widget.state.sources.where((s) => s.enabled).toList();
    final source =
        enabled.where((s) => s.id == _source?.id).firstOrNull ??
        enabled.firstOrNull;
    if (!identical(source, _source)) {
      _entryGeneration++;
      _source = source;
      _entry = null;
      _future = null;
    }
  }

  void _selectSource(String? id) {
    final source = widget.state.sources
        .where((s) => s.enabled && s.id == id)
        .firstOrNull;
    if (source == null || source.id == _source?.id) return;
    setState(() {
      _entryGeneration++;
      _source = source;
      _entry = null;
      _future = null;
    });
  }

  void _loadEntry((String, String) entry) {
    final source = _source;
    if (source == null) return;
    setState(() {
      _entryGeneration++;
      _entry = entry;
      _future = _fetchEntry(source, entry.$2);
      // 下一帧 FutureBuilder 才订阅；即时失败或提前离页也要接住异常。
      // ignore 不改变原 Future，界面仍会收到错误并显示重试入口。
      _future!.ignore();
    });
  }

  Future<Paged<Book>> _fetchEntry(
    ComicSource source,
    String url, {
    int page = 1,
    String? nextUrl,
  }) async {
    final state = widget.state;
    try {
      final result = await SourceService.instance
          .runtimeFor(source)
          .explore(url, page: page, nextUrl: nextUrl);
      await state.reportSourceHealth(
        [source.id],
        const {},
        observedSources: [source],
      );
      return result;
    } catch (e) {
      await state.reportSourceHealth(
        const [],
        {source.id: e.toString()},
        observedSources: [source],
      );
      rethrow;
    }
  }

  void _openSources() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => SourceScreen(state: widget.state)));

  void _openSearch() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => SearchScreen(state: widget.state)));

  /// 下拉刷新当前分类：保留旧结果直到新数据到达（不闪骨架）。
  Future<void> _refreshCurrent() async {
    final entry = _entry;
    final source = _source;
    if (entry == null || source == null) return;
    final generation = ++_entryGeneration;
    final future = _fetchEntry(source, entry.$2);
    future.ignore();
    try {
      final page = await future;
      if (!mounted || generation != _entryGeneration) return;
      setState(() {
        _future = SynchronousFuture(page);
      });
    } catch (_) {
      if (!mounted || generation != _entryGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('刷新失败，已保留原列表'),
          action: SnackBarAction(
            label: '重试',
            onPressed: () {
              if (mounted && generation == _entryGeneration) {
                _refreshKey.currentState?.show();
              }
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.brightness == Brightness.light
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainerLow;
    final enabled = widget.state.sources.where((s) => s.enabled).toList();
    final source = _source;
    final entries = source == null
        ? const <(String, String)>[]
        : SourceService.instance.runtimeFor(source).exploreEntries();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: ScreenTitle('探索'),
            ),
            Expanded(
              child: source == null
                  ? EmptyStateView(
                      icon: Icons.travel_explore,
                      title: '暂无可用漫画源',
                      message: '添加或启用一个漫画源，开始发现喜欢的漫画。',
                      actionLabel: '管理源',
                      onAction: _openSources,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Semantics(
                            label: '漫画源',
                            child: ButtonTheme(
                              // 菜单沿用入口宽度，避免默认外扩吃掉页面两侧留白。
                              alignedDropdown: true,
                              child: Tooltip(
                                message: '切换漫画源',
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(source.id),
                                  initialValue: source.id,
                                  isExpanded: true,
                                  itemHeight: null,
                                  icon: const Icon(Icons.expand_more, size: 20),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    filled: true,
                                    fillColor: surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: scheme.outlineVariant.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  items: enabled.map((s) {
                                    final name = s.name.trim().isEmpty
                                        ? s.id
                                        : s.name;
                                    return DropdownMenuItem(
                                      value: s.id,
                                      child: Tooltip(
                                        message: name,
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _selectSource,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (entries.isNotEmpty)
                          // 渐隐只占右侧留白，滚到底时末项仍完整；长分类名保留提示。
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [Colors.white, Colors.transparent],
                                ).createShader(
                                  Rect.fromLTWH(
                                    bounds.right - 20,
                                    bounds.top,
                                    20,
                                    bounds.height,
                                  ),
                                ),
                            blendMode: BlendMode.dstIn,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Row(
                                spacing: 8,
                                children: entries
                                    .map(
                                      (entry) => Tooltip(
                                        message: entry.$1,
                                        child: FilterChoiceChip(
                                          label: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.sizeOf(
                                                    context,
                                                  ).width *
                                                  0.7,
                                            ),
                                            child: Text(
                                              entry.$1,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          selected: _entry == entry,
                                          onSelected: (_) => _loadEntry(entry),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        if (entries.isNotEmpty) const SizedBox(height: 12),
                        Expanded(child: _content(entries)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<(String, String)> entries) {
    if (entries.isEmpty) {
      return EmptyStateView(
        icon: Icons.explore_off_outlined,
        title: '当前源暂无探索分类',
        message: '可以切换上方漫画源，或通过搜索查找漫画。',
        actionLabel: '去搜索',
        onAction: _openSearch,
      );
    }
    final entry = _entry;
    if (entry == null) {
      return const EmptyStateView(
        icon: Icons.explore_outlined,
        title: '选一个分类开始探索',
        message: '点按上方分类，发现下一部喜欢的漫画。',
      );
    }
    final source = _source!;
    return FutureBuilder<Paged<Book>>(
      // 每次切分类或重试都丢弃旧快照，避免旧漫画短暂出现在新分类下。
      key: ObjectKey(_future),
      future: _future,
      builder: (context, snapshot) {
        final Widget content;
        if (snapshot.connectionState != ConnectionState.done) {
          content = const BookListSkeleton(key: ValueKey('loading'));
        } else if (snapshot.hasError) {
          content = EmptyStateView(
            key: const ValueKey('error'),
            icon: Icons.cloud_off_outlined,
            title: '暂时无法加载漫画',
            message: '检查网络后重试，或切换上方漫画源。',
            actionLabel: '重试',
            onAction: () => _loadEntry(entry),
          );
        } else {
          final books = snapshot.data!.items;
          content = books.isEmpty
              ? EmptyStateView(
                  key: const ValueKey('empty'),
                  icon: Icons.auto_stories_outlined,
                  title: '这个分类还没有漫画',
                  message: '试试其他分类，或稍后重新加载。',
                  actionLabel: '重新加载',
                  onAction: () => _loadEntry(entry),
                )
              : ExploreResults(
                  key: ObjectKey(snapshot.data),
                  firstPage: snapshot.data!,
                  entryUrl: entry.$2,
                  state: widget.state,
                  refreshKey: _refreshKey,
                  onRefresh: _refreshCurrent,
                  loadPage: (page, nextUrl) => _fetchEntry(
                    source,
                    entry.$2,
                    page: page,
                    nextUrl: nextUrl,
                  ),
                );
        }
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          child: content,
        );
      },
    );
  }
}
