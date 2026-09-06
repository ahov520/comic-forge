import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/search_aggregator.dart';
import 'source_screen.dart';
import 'widgets.dart';

/// 聚合搜索：并发查所有启用源；结果带源标识、同名去重、按源权重排序。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final Map<String, List<Book>> _raw = {}; // 源id → 结果（到达序）
  AggregatedSearch? _agg;
  final Map<String, String> _failed = {};
  bool _searching = false;
  String _query = '';
  int _searchGeneration = 0;
  int _sourceCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {
      if (_controller.text.trim() != _query) {
        // 输入变更后，旧请求仍可回报源健康，但不能覆盖当前页面。
        _searchGeneration++;
        _searching = false;
        _query = '';
        _sourceCount = 0;
        _raw.clear();
        _agg = null;
        _failed.clear();
      }
    });
  }

  void _refill(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focusNode.requestFocus();
  }

  /// 源 id → 显示名（结果标签用）。
  String _sourceName(String id) {
    for (final s in widget.state.sources) {
      if (s.id == id) return s.name.isEmpty ? id : s.name;
    }
    return id;
  }

  bool _isCurrentSearch(int generation) =>
      mounted && generation == _searchGeneration;

  Future<void> _doSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _searching) return;
    final state = widget.state;
    final enabled = state.sources
        .where((s) => s.enabled && s.rules.searchUrl.isNotEmpty)
        .toList();
    final generation = ++_searchGeneration;
    _focusNode.unfocus();
    setState(() {
      _searching = true;
      _query = q;
      _sourceCount = enabled.length;
      _raw.clear();
      _agg = null;
      _failed.clear();
    });
    await state.recordSearch(q);
    if (!_isCurrentSearch(generation)) return;

    final okIds = <String>{};
    final errors = <String, String>{};
    await Future.wait(
      enabled.map((s) async {
        try {
          final page = await SourceService.instance.runtimeFor(s).search(q);
          if (_isCurrentSearch(generation)) {
            setState(() {
              _raw[s.id] = page.items;
              _reaggregate();
            });
          }
          okIds.add(s.id);
        } catch (e) {
          if (_isCurrentSearch(generation)) {
            setState(() => _failed[s.id] = _sourceName(s.id));
          }
          errors[s.id] = e.toString();
        }
      }),
    );
    // 健康回报：成功清零失败计数，失败累加（源页据此标红/一键禁用失效源）。
    await state.reportSourceHealth(okIds, errors);
    if (_isCurrentSearch(generation)) setState(() => _searching = false);
  }

  void _reaggregate() {
    _agg = SearchAggregator.aggregate(Map.of(_raw), (sourceId) {
      for (final s in widget.state.sources) {
        if (s.id == sourceId) return s.weight;
      }
      return 0;
    });
  }

  Widget _historyView(BuildContext context) {
    final history = widget.state.searchHistory;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '最近10词',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (history.isNotEmpty)
              TextButton.icon(
                onPressed: widget.state.clearSearchHistory,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: const Text('清空'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '输入关键词开始聚合搜索',
            message: '输入书名或作者，跨源查找喜欢的漫画。',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in history)
                Tooltip(
                  message: query,
                  child: ActionChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _refill(query),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _resultsView(BuildContext context) {
    final agg = _agg;
    final scheme = Theme.of(context).colorScheme;
    final completed = _raw.length + _failed.length;
    return Column(
      children: [
        if (_searching)
          LinearProgressIndicator(
            value: _sourceCount == 0 ? null : completed / _sourceCount,
            semanticsLabel: '搜索进度',
          ),
        if (_query.isNotEmpty && _sourceCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _searching
                    ? '正在搜索 $completed/$_sourceCount 个源 · 已找到 ${agg?.books.length ?? 0} 条'
                    : '${agg?.books.length ?? 0} 条结果 · ${agg?.sourcesHit ?? 0} 个源命中'
                          '${(agg?.duplicatesRemoved ?? 0) > 0 ? ' · 去重 ${agg!.duplicatesRemoved}' : ''}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: _resultContent(),
          ),
        ),
        if (_failed.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_failed.length} 个源暂时不可用：${_failed.values.join('、')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _resultContent() {
    if (_query.isEmpty) {
      return const EmptyStateView(
        key: ValueKey('prompt'),
        icon: Icons.manage_search_outlined,
        title: '输入关键词开始聚合搜索',
        message: '输入书名或作者，跨源查找喜欢的漫画。',
      );
    }
    if (_sourceCount == 0) {
      return EmptyStateView(
        key: const ValueKey('no-sources'),
        icon: Icons.travel_explore,
        title: '暂无可搜索的源',
        message: '启用一个支持搜索的漫画源后再试。',
        actionLabel: '管理源',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SourceScreen(state: widget.state)),
        ),
      );
    }
    final agg = _agg;
    if (agg != null && agg.books.isNotEmpty) {
      return ListView.builder(
        key: ValueKey('results-$_query'),
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: agg.books.length,
        itemBuilder: (context, i) => BookTile(
          key: ObjectKey(agg.books[i]),
          book: agg.books[i],
          state: widget.state,
          sourceLabel: _sourceName(agg.sourceIds[i]),
        ),
      );
    }
    if (_searching) {
      return const Center(key: ValueKey('loading'), child: Text('搜索中…'));
    }
    if (_raw.isEmpty && _failed.isNotEmpty) {
      return EmptyStateView(
        key: const ValueKey('failed'),
        icon: Icons.cloud_off_outlined,
        title: '暂时无法连接漫画源',
        message: '检查网络，或到「源」页查看源状态后再试。',
        actionLabel: '重新搜索',
        onAction: _doSearch,
      );
    }
    return EmptyStateView(
      key: const ValueKey('empty'),
      icon: Icons.search_off_outlined,
      title: '没有找到相关漫画',
      message: '试试更短的书名、作者名，或换一个关键词。',
      actionLabel: '修改关键词',
      onAction: () {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        _focusNode.requestFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: '搜索书名、作者…',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空输入',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        _focusNode.requestFocus();
                      },
                    ),
            ),
          ),
          actions: [
            IconButton.filledTonal(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: _searching || _controller.text.trim().isEmpty
                  ? null
                  : _doSearch,
            ),
          ],
        ),
        body: _controller.text.trim().isEmpty
            ? _historyView(context)
            : _resultsView(context),
      ),
    );
  }
}
