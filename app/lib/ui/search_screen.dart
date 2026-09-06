import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// 聚合搜索：并发查所有启用源。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final List<Book> _results = [];
  final Set<String> _failed = {};
  bool _searching = false;
  String _query = '';

  Future<void> _doSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _searching) return;
    final enabled = widget.state.sources.where((s) => s.enabled && s.rules.searchUrl.isNotEmpty);
    setState(() {
      _searching = true;
      _query = q;
      _results.clear();
      _failed.clear();
    });
    final okIds = <String>{};
    final errors = <String, String>{};
    await Future.wait(enabled.map((s) async {
      try {
        final page = await SourceService.instance.runtimeFor(s).search(q);
        if (mounted) setState(() => _results.addAll(page.items));
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

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? '输入关键词开始聚合搜索' : (_searching ? '搜索中…' : '没有结果'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) =>
                        BookTile(book: _results[i], state: widget.state),
                  ),
          ),
          if (_failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('以下源失败: ${_failed.join('、')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
