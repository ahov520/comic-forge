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
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      style: textTheme.titleMedium,
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
          Flexible(
            child: failures.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Text(
                      '暂无失败源',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('search-failure-list'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: failures.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: scheme.outlineVariant),
                    itemBuilder: (context, i) {
                      final failure = failures[i];
                      final (icon, reason) = switch (failure.kind) {
                        SearchSourceFailKind.timeout => (
                          Icons.timer_outlined,
                          '连接超时',
                        ),
                        SearchSourceFailKind.blocked => (
                          Icons.block_outlined,
                          '域名已屏蔽',
                        ),
                        SearchSourceFailKind.error => (
                          Icons.cloud_off_outlined,
                          '连接失败',
                        ),
                      };
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        minTileHeight: 60,
                        minVerticalPadding: 12,
                        minLeadingWidth: 18,
                        horizontalTitleGap: 12,
                        leading: Icon(
                          icon,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        title: Text(failure.name, style: textTheme.bodyMedium),
                        subtitle: Text(
                          reason,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 44),
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                textStyle: textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onManageSources,
              icon: const Icon(Icons.source_outlined, size: 18),
              label: const Text('管理源', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
