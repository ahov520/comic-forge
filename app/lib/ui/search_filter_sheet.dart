import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/search_filters.dart';

class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({super.key, required this.state});
  final AppState state;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late bool _healthy = widget.state.searchFilters.onlyHealthy;
  late Set<String>? _ids = widget.state.searchFilters.sourceIds?.toSet();

  SearchFilters get _filters =>
      SearchFilters(onlyHealthy: _healthy, sourceIds: _ids);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final sources = widget.state.sources
          .where((s) => s.rules.searchUrl.isNotEmpty)
          .toList();
      final count = sources.where(_filters.accepts).length;
      return SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  '搜索筛选 · $count 个可用源',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    SwitchListTile(
                      title: const Text('仅健康源'),
                      subtitle: const Text('跳过连续失败 3 次的源，未检测源仍参与'),
                      value: _healthy,
                      onChanged: (value) => setState(() => _healthy = value),
                    ),
                    SwitchListTile(
                      title: const Text('指定漫画源'),
                      subtitle: Text(
                        _ids == null ? '搜索所有已启用且支持搜索的源' : '仅搜索勾选的源，与健康筛选共同生效',
                      ),
                      value: _ids != null,
                      onChanged: (value) => setState(() {
                        _ids = value
                            ? sources
                                  .where((s) => s.enabled)
                                  .map((s) => s.id)
                                  .toSet()
                            : null;
                      }),
                    ),
                    if (_ids != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          children: [
                            TextButton(
                              onPressed: () => setState(
                                () => _ids = sources
                                    .where((s) => s.enabled)
                                    .map((s) => s.id)
                                    .toSet(),
                              ),
                              child: const Text('全选'),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _ids = {}),
                              child: const Text('全不选'),
                            ),
                          ],
                        ),
                      ),
                      for (final source in sources)
                        CheckboxListTile(
                          key: ValueKey('search-source-${source.id}'),
                          title: Text(
                            source.name.isEmpty ? source.id : source.name,
                          ),
                          subtitle: Text(
                            !source.enabled
                                ? '已停用'
                                : source.isUnhealthy
                                ? '连续失败 ${source.failCount} 次'
                                : '可参与搜索',
                          ),
                          value: _ids!.contains(source.id),
                          onChanged: source.enabled
                              ? (value) => setState(() {
                                  if (value == true) {
                                    _ids!.add(source.id);
                                  } else {
                                    _ids!.remove(source.id);
                                  }
                                })
                              : null,
                        ),
                      if (sources.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('还没有支持搜索的源'),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _healthy = false;
                        _ids = null;
                      }),
                      child: const Text('重置'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_filters),
                      child: const Text('应用筛选'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
