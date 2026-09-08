import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/reading_history.dart';
import '../state/reading_stats.dart';
import 'widgets.dart';

class ComicReadingStatsScreen extends StatelessWidget {
  const ComicReadingStatsScreen({
    super.key,
    required this.stats,
    this.sources = const [],
  });

  final ReadingStats stats;
  final List<ComicSource> sources;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('按漫画统计')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: stats,
        builder: (context, _) {
          final comics = stats.comics;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${comics.length} 本漫画 · 按最近阅读排序',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '单本统计从本次升级开始记录，之前的阅读仍保留在累计统计中。'
                        '每次进入已加载章节计为一次阅读，暂停后继续不重复计次。',
                      ),
                    ],
                  ),
                ),
              ),
              if (comics.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Icons.menu_book_outlined,
                    title: '还没有单本阅读统计',
                    message: '开始阅读后，这里会显示每本漫画的阅读时长、话数与最近阅读。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList.builder(
                    itemCount: comics.length,
                    itemBuilder: (context, index) {
                      final comic = comics[index];
                      final source = sources
                          .where((source) => source.id == comic.sourceId)
                          .firstOrNull;
                      final sourceName = source == null
                          ? (comic.sourceId?.isNotEmpty == true
                                ? '来源已移除'
                                : '未知来源')
                          : (source.name.trim().isEmpty
                                ? '未命名来源'
                                : source.name);
                      final at = comic.lastReadAt.toLocal();
                      final date =
                          '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
                      return Card(
                        key: ValueKey(comic.key),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comic.name.trim().isEmpty
                                    ? '未命名漫画'
                                    : comic.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(sourceName),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  Text(formatReadingDuration(comic.duration)),
                                  Text('${comic.chapterCount} 话'),
                                  Text('${comic.sessionCount} 次阅读'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '最近阅读：$date ${readingHistoryTime(at.millisecondsSinceEpoch)}',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
