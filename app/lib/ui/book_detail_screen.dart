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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _book = null;
    _source = _findSource();
    _future = _source == null
        ? Future.error('未找到来源源（可能已被移除或禁用）')
        : SourceService.instance.runtimeFor(_source!).detail(widget.book.bookUrl);
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
                                      style: TextStyle(color: scheme.outline)),
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
                    child: Text('章节 (${chapters.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                SliverList.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, i) {
                    final ch = chapters[i];
                    return ListTile(
                      dense: true,
                      leading: Text('${i + 1}',
                          style: TextStyle(color: scheme.outline)),
                      title: Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        if (_source != null) {
                          openReader(context,
                              SourceService.instance.runtimeFor(_source!), book, ch);
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
