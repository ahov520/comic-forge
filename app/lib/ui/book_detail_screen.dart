import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// 书籍详情 + 章节列表。
class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({super.key, required this.book, required this.appState});
  final Book book;
  final AppState appState;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Future<(Book, List<Chapter>)> _future;
  Book? _book;
  ComicSource? _source;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _book = null;
    _source = _findSource();
    final cached = widget.appState.detailCacheFor(widget.book.bookUrl);
    if (cached != null) {
      // stale-while-revalidate：先秒开缓存，再后台刷新（失败静默回退缓存）
      _fromCache = true;
      final cachedPair = (cached.book, cached.chapters);
      _future = Future<(Book, List<Chapter>)>.value(cachedPair);
      _refreshInBackground(cachedPair);
      return;
    }
    _fromCache = false;
    _future = _source == null
        ? Future.error('未找到来源源（可能已被移除或禁用）')
        : _fetchDetail();
  }

  Future<(Book, List<Chapter>)> _fetchDetail() async {
    final (book, chapters) =
        await SourceService.instance.runtimeFor(_source!).detail(widget.book.bookUrl);
    await widget.appState.saveDetailCache(book, chapters);
    return (book, chapters);
  }

  Future<void> _refreshInBackground((Book, List<Chapter>) cachedPair) async {
    if (_source == null) return;
    try {
      final fresh = await _fetchDetail();
      if (mounted) {
        setState(() {
          _fromCache = false;
          _future = Future<(Book, List<Chapter>)>.value(fresh);
        });
      }
    } catch (_) {
      // 网络失败：保持缓存内容，不打断阅读
      _future = Future<(Book, List<Chapter>)>.value(cachedPair);
    }
  }

  ComicSource? _findSource() {
    for (final s in widget.appState.sources) {
      if (s.id == widget.book.sourceId && s.enabled) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: FutureBuilder<(Book, List<Chapter>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.book.name)),
              body: ErrorView(error: snap.error, onRetry: () => setState(_load)),
            );
          }
          if (!snap.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.book.name)),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          final (book, chapters) = snap.data!;
          _book ??= book;
          final prog = widget.appState.progressFor(widget.book.bookUrl);
          final savedIdx = (prog != null)
              ? chapters.indexWhere((c) => c.url == prog.chapterUrl)
              : -1;
          return Scaffold(
            appBar: AppBar(
              title: Text(book.name),
              actions: [
                IconButton(
                  icon: Icon(
                    widget.appState.inShelf(widget.book) ? Icons.favorite : Icons.favorite_border,
                  ),
                  onPressed: () => widget.appState.toggleShelf(widget.book),
                ),
              ],
            ),
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BookCover(url: book.coverUrl, width: 110, height: 150),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(book.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (book.author.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(book.author,
                                      style: TextStyle(color: scheme.onSurfaceVariant)),
                                ),
                              if (book.kind.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    children: book.kind
                                        .split(RegExp(r'[,，|/\s]+'))
                                        .where((k) => k.isNotEmpty)
                                        .take(5)
                                        .map((k) => Chip(
                                              label: Text(k),
                                              labelStyle: const TextStyle(fontSize: 11),
                                              visualDensity: VisualDensity.compact,
                                            ))
                                        .toList(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (book.introduce.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(book.introduce,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text('章节 (${chapters.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        if (_fromCache)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: const Text('离线目录', style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                        if (savedIdx >= 0)
                          FilledButton.tonalIcon(
                            onPressed: () {
                              if (_source != null) {
                                openReader(context,
                                    SourceService.instance.runtimeFor(_source!),
                                    book, chapters, savedIdx, widget.appState);
                              }
                            },
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text('续读 ${savedIdx + 1}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, i) {
                    final ch = chapters[i];
                    final isCurrent = i == savedIdx;
                    return ListTile(
                      dense: true,
                      leading: Text('${i + 1}',
                          style: TextStyle(
                              color: isCurrent
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : null)),
                      title: Text(ch.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: isCurrent
                              ? TextStyle(color: scheme.primary)
                              : null),
                      trailing: isCurrent
                          ? Icon(Icons.bookmark, size: 16,
                              color: scheme.primary)
                          : null,
                      onTap: () {
                        if (_source != null) {
                          openReader(context,
                              SourceService.instance.runtimeFor(_source!),
                              book, chapters, i, widget.appState);
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
