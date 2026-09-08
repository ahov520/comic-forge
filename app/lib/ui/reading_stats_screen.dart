import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/reading_history.dart';
import '../state/reading_stats.dart';
import 'comic_reading_stats_screen.dart';

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({
    super.key,
    required this.stats,
    this.sources = const [],
  });

  final ReadingStats stats;
  final List<ComicSource> sources;

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.stats,
    builder: (context, _) {
      final stats = widget.stats;
      final days = stats.recentDays;
      final maxTime = days.fold<int>(0, (max, day) {
        final time = day.summary.duration.inMilliseconds;
        return time > max ? time : max;
      });
      final textTheme = Theme.of(context).textTheme;
      return Scaffold(
        appBar: AppBar(title: const Text('阅读统计')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SummaryCard(title: '今日阅读', summary: stats.today),
            const SizedBox(height: 12),
            _SummaryCard(title: '累计阅读', summary: stats.total, showDays: true),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('按漫画查看'),
                subtitle: const Text('时长、话数、次数与最近阅读'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComicReadingStatsScreen(
                      stats: stats,
                      sources: widget.sources,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('近 7 日', style: textTheme.titleMedium),
            for (final day in days)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          readingHistoryDay(
                            day.date.millisecondsSinceEpoch,
                            now: stats.now,
                          ),
                        ),
                        Text(formatReadingDuration(day.summary.duration)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 时长由相邻文字朗读，比例条只用于比较，避免读成完成进度。
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                        key: ValueKey(day.date),
                        value: maxTime == 0
                            ? 0
                            : day.summary.duration.inMilliseconds / maxTime,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${day.summary.bookCount} 本漫画 · ${day.summary.chapterCount} 话',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Text(
              '仅计入章节加载成功后的前台阅读时间。漫画和章节按来源去重，重复阅读会累加时长。统计从此版本开始记录。',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.summary,
    this.showDays = false,
  });

  final String title;
  final ReadingStatsSummary summary;
  final bool showDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              formatReadingDuration(summary.duration),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('${summary.bookCount} 本漫画'),
                Text('${summary.chapterCount} 话'),
                if (showDays) Text('${summary.activeDays} 天有阅读'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
