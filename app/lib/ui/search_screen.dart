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
  final Map<String, List<Book>> _raw = {}; // 源id → 结果（到达序）
  AggregatedSearch? _agg;
  final Set<String> _failed = {};
  bool _searching = false;
  String _query = '';

  /// 源 id → 显示名（结果标签用）。
  String _sourceName(String id) {
    for (final s in widget.state.sources) {
      if (s.id == id) return s.name.isEmpty ? id : s.name;
    }
    return id;
  }

  Future<void> _doSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _searching) return;
    final enabled = widget.state.sources.where((s) => s.enabled && s.rules.searchUrl.isNotEmpty);
    setState(() {
      _searching = true;
      _query = q;
      _raw.clear();
      _agg = null;
      _failed.clear();
    });
    final okIds = <String>{};
    final errors = <String, String>{};
    await Future.wait(enabled.map((s) async {
      try {
        final page = await SourceService.instance.runtimeFor(s).search(q);
        if (mounted) {
          setState(() => _raw[s.id] = page.items);
          _reaggregate();
        }
        okIds.add(s.id);
      } catch (e) {
        if (mounted) setState(() => _failed.add(s.name));
        errors[s.id] = e.toString();
      }
    }));
    // 健康回报：成功清零失败计数，失败累加（源页据此标红/一键禁用失效源）
    await widget.state.reportSourceHealth(okIds, errors);
    if (mounted) setState(() => _searching = false);
  }

  void _reaggregate() {
    setState(() {
      _agg = SearchAggregator.aggregate(
        Map.of(_raw),
        (sourceId) {
          for (final s in widget.state.sources) {
            if (s.id == sourceId) return s.weight;
          }
          return 0;
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final agg = _agg;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
          decoration: const InputDecoration(hintText: '搜索全部源…', border: InputBorder.none),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
        ],
      ),
      body: Column(
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
                  style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(
            child: (agg == null || agg.books.isEmpty)
                ? Center(
                    child: Text(
                      _query.isEmpty ? '输入关键词开始聚合搜索' : (_searching ? '搜索中…' : '没有结果'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              child: Text('${_failed.length} 个源失败: ${_failed.join('、')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
