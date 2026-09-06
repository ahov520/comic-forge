import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'book_detail_screen.dart';
import 'widgets.dart';

/// 书架。
class ShelfScreen extends StatelessWidget {
  const ShelfScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        if (state.shelf.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_bookmark_outlined,
                    size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                const Text('书架空空如也'),
                const SizedBox(height: 4),
                Text('去「探索」或「搜索」收藏第一部漫画吧',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            childAspectRatio: 0.62,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: state.shelf.length,
          itemBuilder: (context, i) {
            final b = state.shelf[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookDetailScreen(book: b, appState: state),
              )),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: BookCover(url: b.coverUrl)),
                  const SizedBox(height: 6),
                  Text(b.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
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
                        return SizedBox(
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
                                  return const Center(child: CircularProgressIndicator());
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
