import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'book_detail_screen.dart';
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
  /// 筛选：0=全部 1=连载中 2=已完结（按 book.kind 关键词，缺失归入全部）
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        // 筛选：kind 含「完结」→ 已完结；kind 非空且不含「完结」→ 连载中；kind 空 → 仅「全部」可见
        final books =
            widget.state.shelf.where((b) {
              switch (_filter) {
                case 2:
                  return b.kind.contains('完结');
                case 1:
                  return b.kind.isNotEmpty && !b.kind.contains('完结');
                default:
                  return true;
              }
            }).toList()..sort((a, b) {
              final pa = widget.state.progress[a.bookUrl]?.at ?? 0;
              final pb = widget.state.progress[b.bookUrl]?.at ?? 0;
              return pb.compareTo(pa);
            });
        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: ScreenTitle('书架'),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['全部', '连载中', '已完结']
                        .asMap()
                        .entries
                        .map(
                          (e) => FilterChoiceChip(
                            label: Text(e.value),
                            selected: _filter == e.key,
                            onSelected: (_) => setState(() => _filter = e.key),
                          ),
                        )
                        .toList(),
                  ),
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
                          title: '这个分类还没有漫画',
                          message: '试试其他分类，或查看书架中的全部漫画。',
                          actionLabel: '查看全部',
                          onAction: () => setState(() => _filter = 0),
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final b = books[i];
                      final prog = widget.state.progress[b.bookUrl];
                      final progLabel =
                          prog == null || prog.chapterTitle.isEmpty
                          ? ''
                          : prog.chapterTitle;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookDetailScreen(
                              book: b,
                              appState: widget.state,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: BookCover(url: b.coverUrl),
                                    ),
                                    if (progLabel.isNotEmpty)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          color: Colors.black54,
                                          child: Text(
                                            progLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }, childCount: books.length),
                  ),
                ),
            ],
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
      _source = source;
      _entry = null;
      _future = null;
    });
  }

  void _loadEntry((String, String) entry) {
    final source = _source;
    if (source == null) return;
    setState(() {
      _entry = entry;
      _future = _fetchEntry(source, entry.$2);
      // 下一帧 FutureBuilder 才订阅；即时失败或提前离页也要接住异常。
      // ignore 不改变原 Future，界面仍会收到错误并显示重试入口。
      _future!.ignore();
    });
  }

  Future<Paged<Book>> _fetchEntry(ComicSource source, String url) async {
    final state = widget.state;
    try {
      final page = await SourceService.instance.runtimeFor(source).explore(url);
      await state.reportSourceHealth([source.id], const {});
      return page;
    } catch (e) {
      await state.reportSourceHealth(const [], {source.id: e.toString()});
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
    final future = _fetchEntry(source, entry.$2);
    future.ignore();
    try {
      final page = await future;
      if (!mounted || !identical(_entry, entry)) return;
      setState(() {
        _future = Future<Paged<Book>>.value(page);
      });
    } catch (e) {
      if (!mounted || !identical(_entry, entry)) return;
      setState(() {
        _future = Future<Paged<Book>>.error(e);
      });
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
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Semantics(
                            label: '漫画源',
                            child: Tooltip(
                              message: '切换漫画源',
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(source.id),
                                initialValue: source.id,
                                isExpanded: true,
                                itemHeight: null,
                                icon: const Icon(Icons.expand_more, size: 20),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
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
                        if (entries.isNotEmpty)
                          // 保留右端渐隐提示；高度随字号增长，长分类名可查看完整提示。
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              stops: [0.9, 1.0],
                              colors: [Colors.white, Colors.transparent],
                            ).createShader(bounds),
                            blendMode: BlendMode.dstIn,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Row(
                                children: entries
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: Tooltip(
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
                                            onSelected: (_) =>
                                                _loadEntry(entry),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
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
              : RefreshIndicator(
                  key: const ValueKey('results'),
                  onRefresh: _refreshCurrent,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: books.length,
                    itemBuilder: (context, i) => BookTile(
                      key: ObjectKey(books[i]),
                      book: books[i],
                      state: widget.state,
                    ),
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
