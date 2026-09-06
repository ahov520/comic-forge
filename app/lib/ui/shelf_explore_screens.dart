import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'book_detail_screen.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// 书架。
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  /// 筛选：0=全部 1=连载中 2=已完结（按 book.kind 关键词，缺失归入全部）
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        if (widget.state.shelf.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_bookmark_outlined,
                    size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text('书架空空如也'),
                const SizedBox(height: 4),
                Text('去「探索」或「搜索」收藏第一部漫画吧',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }
        // 筛选：kind 含「完结」→ 已完结；kind 非空且不含「完结」→ 连载中；kind 空 → 仅「全部」可见
        final books = widget.state.shelf.where((b) {
          switch (_filter) {
            case 2:
              return b.kind.contains('完结');
            case 1:
              return b.kind.isNotEmpty && !b.kind.contains('完结');
            default:
              return true;
          }
        }).toList()
          ..sort((a, b) {
            final pa = widget.state.progress[a.bookUrl]?.at ?? 0;
            final pb = widget.state.progress[b.bookUrl]?.at ?? 0;
            return pb.compareTo(pa);
          });
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('书架',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: ['全部', '连载中', '已完结']
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: _filter == e.key,
                              onSelected: (_) =>
                                  setState(() => _filter = e.key),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            if (books.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child: Text('该分类暂无藏书',
                          style: TextStyle(color: scheme.onSurfaceVariant))),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final b = books[i];
                      final prog = widget.state.progress[b.bookUrl];
                      final progLabel = prog == null || prog.chapterTitle.isEmpty
                          ? ''
                          : prog.chapterTitle;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => BookDetailScreen(
                                    book: b, appState: widget.state))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: Stack(children: [
                              Positioned.fill(
                                  child: BookCover(url: b.coverUrl)),
                              if (progLabel.isNotEmpty)
                                Positioned(
                                  left: 0, right: 0, bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    color: Colors.black54,
                                    child: Text(progLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white)),
                                  ),
                                ),
                            ])),
                          const SizedBox(height: 6),
                          Text(b.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  },
                    childCount: books.length,
                  ),
                ),
              ),
          ],
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
  String? _entry;
  late Future<Paged<Book>> _future;

  @override
  void initState() {
    super.initState();
    _pickDefaultSource();
  }

  void _pickDefaultSource() {
    final enabled = widget.state.sources.where((s) => s.enabled).toList();
    _source = enabled.isEmpty ? null : enabled.first;
    _entry = null;
    _future = Future.value(Paged(const []));
  }

  void _loadEntry(String entry) {
    final src = _source;
    if (src == null) return;
    final entries = SourceService.instance.runtimeFor(src).exploreEntries();
    final url = entries.firstWhere((e) => e.$1 == entry, orElse: () => ('', entry)).$2;
    setState(() {
      _entry = entry;
      _future = SourceService.instance
          .runtimeFor(src)
          .explore(url)
          .then((p) {
        widget.state.reportSourceHealth([src.id], const {});
        return p;
      }).catchError((Object e) {
        widget.state.reportSourceHealth(const [], {src.id: e.toString()});
        throw e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final enabled = widget.state.sources.where((s) => s.enabled).toList();
        final source = _source ?? (enabled.isEmpty ? null : enabled.first);
        return Scaffold(
          appBar: AppBar(
            title: const Text('探索'),
            actions: [
              if (enabled.isNotEmpty)
                DropdownButton<ComicSource>(
                  value: source,
                  underline: const SizedBox(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  items: enabled
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: (s) => setState(() {
                    _source = s;
                    _entry = null;
                  }),
                ),
            ],
          ),
          body: enabled.isEmpty
              ? const Center(child: Text('还没有可用源，先去「源」页订阅仓库'))
              : Column(
                  children: [
                    if (source != null)
                      Builder(builder: (context) {
                        final entries =
                            SourceService.instance.runtimeFor(source).exploreEntries();
                        if (entries.isEmpty) return const SizedBox(height: 8);
                        // 右端渐隐：提示分类条可横向滚动，避免 chip 被硬裁的观感
                        return ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            stops: [0.9, 1.0],
                            colors: [Colors.white, Colors.transparent],
                          ).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: entries
                                  .map((e) => Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: FilterChip(
                                          label: Text(e.$1),
                                          selected: _entry == e.$1,
                                          onSelected: (_) => _loadEntry(e.$1),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        );
                      }),
                    Expanded(
                      child: _entry == null
                          ? const Center(child: Text('选一个分类开始探索'))
                          : FutureBuilder<Paged<Book>>(
                              future: _future,
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return ErrorView(error: snap.error,
                                      onRetry: () => _loadEntry(_entry!));
                                }
                                if (!snap.hasData) {
                                  // 骨架网格：与书架封面网格同构，秒开观感
                                  return GridView.builder(
                                    padding: const EdgeInsets.all(12),
                                    gridDelegate:
                                        const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 120,
                                      childAspectRatio: 0.62,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: 8,
                                    itemBuilder: (context, i) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                            child: SkeletonBox(
                                                height: 140, radius: 10)),
                                        const SizedBox(height: 6),
                                        SkeletonBox(height: 10, radius: 4),
                                      ],
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  itemCount: snap.data!.items.length,
                                  itemBuilder: (context, i) =>
                                      BookTile(book: snap.data!.items[i], state: widget.state),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
