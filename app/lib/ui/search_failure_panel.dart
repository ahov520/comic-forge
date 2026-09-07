import 'package:flutter/material.dart';

import '../state/search_aggregator.dart';

/// 聚合失败详情独立滚动，源名再长也不挤占主页面的搜索结果。
class SearchFailurePanel extends StatelessWidget {
  const SearchFailurePanel({
    super.key,
    required this.failures,
    required this.onManageSources,
  });

  final List<SearchSourceFailure> failures;
  final VoidCallback onManageSources;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      '未响应的源 · ${failures.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: failures.isEmpty
                ? const Center(child: Text('暂无失败源'))
                : ListView.builder(
                    key: const ValueKey('search-failure-list'),
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: failures.length,
                    itemBuilder: (context, i) {
                      final failure = failures[i];
                      final timedOut =
                          failure.kind == SearchSourceFailKind.timeout;
                      return ListTile(
                        leading: Icon(
                          timedOut
                              ? Icons.timer_outlined
                              : Icons.cloud_off_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                        title: Text(failure.name),
                        subtitle: Text(timedOut ? '连接超时' : '连接失败'),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton.tonalIcon(
              onPressed: onManageSources,
              icon: const Icon(Icons.source_outlined),
              label: const Text('管理源'),
            ),
          ),
        ],
      ),
    );
  }
}
