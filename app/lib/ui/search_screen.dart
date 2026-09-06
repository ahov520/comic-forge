import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/search_aggregator.dart';
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
  final Set<String> _failed = {};
  bool _searching = false;
  String _query = '';
  int _searchGeneration = 0;

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
            setState(() => _failed.add(s.name));
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
          Text(
            '输入关键词开始聚合搜索',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
    return Column(
      children: [
        if (_searching) const LinearProgressIndicator(),
        if (agg != null && !_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${agg.books.length} 条结果 · ${agg.sourcesHit} 个源命中'
                '${agg.duplicatesRemoved > 0 ? ' · 去重 ${agg.duplicatesRemoved}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(
          child: (agg == null || agg.books.isEmpty)
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? '输入关键词开始聚合搜索'
                        : (_searching ? '搜索中…' : '没有结果'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: agg.books.length,
                  itemBuilder: (context, i) => BookTile(
                    book: agg.books[i],
                    state: widget.state,
                    sourceLabel: _sourceName(agg.sourceIds[i]),
                  ),
                ),
        ),
        if (_failed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${_failed.length} 个源失败: ${_failed.join('、')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: '搜索全部源…',
              border: InputBorder.none,
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
            IconButton(
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
