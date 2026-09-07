import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'widgets.dart';

/// 同一分类内逐页追加，保留已有卡片和滚动位置；换分类或刷新时重建。
class ExploreResults extends StatefulWidget {
  const ExploreResults({
    super.key,
    required this.firstPage,
    required this.entryUrl,
    required this.state,
    required this.refreshKey,
    required this.onRefresh,
    required this.loadPage,
  });

  final Paged<Book> firstPage;
  final String entryUrl;
  final AppState state;
  final GlobalKey<RefreshIndicatorState> refreshKey;
  final Future<void> Function() onRefresh;
  final Future<Paged<Book>> Function(int page, String? nextUrl) loadPage;

  @override
  State<ExploreResults> createState() => _ExploreResultsState();
}

class _ExploreResultsState extends State<ExploreResults> {
  final _books = <Book>[];
  final _seen = <Object>{};
  late final bool _usesPageNumbers;
  late final bool _supportsPagination;
  late bool _hasMore;
  late bool _usesNextLinks;
  String? _nextUrl;
  int _page = 1;
  bool _loadingMore = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // 与引擎使用同一套模板替换，包含单/双括号、裸 searchPage 与算术偏移。
    _usesPageNumbers =
        renderUrlTemplate(widget.entryUrl, {'page': '1', 'searchPage': '1'}) !=
        renderUrlTemplate(widget.entryUrl, {'page': '2', 'searchPage': '2'});
    _nextUrl = _nextLink(widget.firstPage);
    _usesNextLinks = _nextUrl != null;
    _hasMore = _usesPageNumbers || _nextUrl != null;
    _supportsPagination = _hasMore;
    _append(widget.firstPage.items);
  }

  String? _nextLink(Paged<Book> page) {
    final next = page.nextPage?.trim();
    return next == null || next.isEmpty ? null : next;
  }

  bool _append(List<Book> books) {
    final before = _books.length;
    for (final book in books) {
      final Object identity = book.bookUrl.isNotEmpty
          ? book.bookUrl
          : (book.name, book.author);
      if (_seen.add(identity)) _books.add(book);
    }
    return _books.length > before;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadFailed = false;
    });
    try {
      final next = await widget.loadPage(_page + 1, _nextUrl);
      if (!mounted) return;
      setState(() {
        _page++;
        final added = _append(next.items);
        _nextUrl = _nextLink(next);
        _usesNextLinks = _usesNextLinks || _nextUrl != null;
        // 空页或整页重复均停止，避免固定首屏的源不断追加相同漫画。
        _hasMore =
            added && (_usesNextLinks ? _nextUrl != null : _usesPageNumbers);
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: !_hasMore
          ? Text(
              '已经到底了',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadFailed) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '暂时无法加载更多',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.primary,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _loadFailed ? Icons.refresh : Icons.expand_more,
                          size: 20,
                        ),
                  label: Text(
                    _loadingMore
                        ? '加载中…'
                        : _loadFailed
                        ? '重试加载'
                        : '加载更多',
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    key: widget.refreshKey,
    onRefresh: widget.onRefresh,
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _books.length + (_supportsPagination ? 1 : 0),
      itemBuilder: (context, i) => i == _books.length
          ? _footer(context)
          : BookTile(
              key: ObjectKey(_books[i]),
              book: _books[i],
              state: widget.state,
            ),
    ),
  );
}
