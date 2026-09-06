import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/source_share.dart';
import 'widgets.dart';
import 'skeleton.dart';

/// 书籍详情 + 章节列表。
class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({
    super.key,
    required this.book,
    required this.appState,
    this.detailLoaderOverride,
  });
  final Book book;
  final AppState appState;

  /// 详情加载器（测试接缝；null 用真实源运行时）。
  final Future<(Book, List<Chapter>)> Function(String bookUrl)?
      detailLoaderOverride;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Future<(Book, List<Chapter>)> _future;
  Book? _book;
  ComicSource? _source;
  ComicSource? _disabledSource; // 来源源存在但被禁用 → 提供一键启用
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _book = null;
    _source = _findSource();
    _disabledSource = null;
    if (_source == null) {
      for (final s in widget.appState.sources) {
        if (s.id == widget.book.sourceId && !s.enabled) {
          _disabledSource = s;
          break;
        }
      }
    }
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
        ? Future.error('未找到可用的来源源')
        : _fetchDetail();
  }

  /// 一键启用被禁用的来源源并重新加载（体检自动禁用后的死路解法）。
  Future<void> _enableSourceAndReload() async {
    final id = _disabledSource?.id;
    if (id == null) return;
    await widget.appState.toggleSource(id);
    if (mounted) setState(_load);
  }

  Future<(Book, List<Chapter>)> _fetchDetail() async {
    final (book, chapters) = widget.detailLoaderOverride != null
        ? await widget.detailLoaderOverride!(widget.book.bookUrl)
        : await SourceService.instance
            .runtimeFor(_source!)
            .detail(widget.book.bookUrl);
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
              body: ErrorView(
                error: snap.error,
                onRetry: () => setState(_load),
                icon: _disabledSource != null
                    ? Icons.block_outlined
                    : Icons.cloud_off_outlined,
                actionLabel: _disabledSource != null
                    ? '启用「${_disabledSource!.name}」并重试'
                    : null,
                onAction: _disabledSource != null ? _enableSourceAndReload : null,
              ),
            );
          }
          if (!snap.hasData) {
            // 骨架屏：结构对齐真实布局（封面块+文字条+章节行），秒开观感
            return Scaffold(
              appBar: AppBar(title: Text(widget.book.name)),
              body: const DetailSkeleton(),
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
                if (_source != null)
                  IconButton(
                    tooltip: '复制本书源 JSON（可分享）',
                    icon: const Icon(Icons.ios_share),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: sourceShareJson(_source!)));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('已复制源 JSON，对方可在「源 → 剪贴板导入」粘贴使用')),
                        );
                      }
                    },
                  ),
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
