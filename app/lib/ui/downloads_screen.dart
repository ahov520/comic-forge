import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/download_queue.dart';
import 'widgets.dart';

void openDownloadedChapter(
  BuildContext context,
  AppState state,
  DownloadTask task,
) {
  final catalog = state.downloads.catalogFor(task);
  if (catalog == null || task.status != DownloadStatus.completed) return;
  final chapters = [...catalog.chapters];
  var index = chapters.indexWhere((chapter) => chapter.url == task.chapter.url);
  if (index < 0) {
    index = chapters.length;
    chapters.add(task.chapter);
  }
  final source = state.sources
      .where((s) => s.id == catalog.book.sourceId && s.enabled)
      .firstOrNull;
  final runtime = source != null
      ? SourceService.instance.runtimeFor(source)
      : SourceRuntime(
          source: ComicSource.fromJson({
            'id': catalog.book.sourceId,
            'name': '离线漫画',
            'url': catalog.book.bookUrl,
            'rules': <String, dynamic>{},
          }),
          fetcher: SourceService.instance.fetcher,
        );
  openReader(context, runtime, catalog.book, chapters, index, state);
}

String downloadStatusLabel(DownloadTask task) => switch (task.status) {
  DownloadStatus.queued => '等待下载',
  DownloadStatus.downloading =>
    task.imageUrls.isEmpty
        ? '正在解析图片…'
        : '下载中 ${task.downloadedPages}/${task.imageUrls.length} 张',
  DownloadStatus.completed => '已下载 ${task.imageUrls.length} 张 · 点击阅读',
  DownloadStatus.failed =>
    '下载失败 · ${task.downloadedPages}/${task.imageUrls.length} 张',
};

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.state});

  final AppState state;

  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请检查可用空间后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = state.downloads;
    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        final tasks = queue.tasks;
        final completed = tasks
            .where((t) => t.status == DownloadStatus.completed)
            .length;
        final failed = tasks
            .where((t) => t.status == DownloadStatus.failed)
            .length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('下载管理'),
            actions: [
              IconButton(
                tooltip: '重试全部失败任务',
                onPressed: failed == 0
                    ? null
                    : () => _action(context, queue.retryFailed),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: !queue.supported
              ? const EmptyStateView(
                  icon: Icons.download_outlined,
                  title: '当前平台暂不支持离线下载',
                  message: '请在 Android 或桌面应用中使用。',
                )
              : tasks.isEmpty
              ? const EmptyStateView(
                  icon: Icons.download_outlined,
                  title: '还没有下载任务',
                  message: '在漫画详情页选择章节，或选中未读章节批量下载。',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已完成 $completed/${tasks.length} 话'
                            '${failed > 0 ? ' · 失败 $failed 话' : ''}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            queue.storageError ?? '下载在应用运行时继续，重新打开后恢复未完成任务。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final book = queue.catalogFor(task)?.book;
                          return ListTile(
                            key: ValueKey(task.id),
                            title: Text(
                              '${book?.name ?? '漫画'} · ${task.chapter.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(downloadStatusLabel(task)),
                                if (task.status ==
                                    DownloadStatus.downloading) ...[
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: task.imageUrls.isEmpty
                                        ? null
                                        : task.downloadedPages /
                                              task.imageUrls.length,
                                  ),
                                ],
                                if (task.error != null) Text(task.error!),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (task.status == DownloadStatus.failed)
                                  IconButton(
                                    tooltip: '重试 ${task.chapter.title}',
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () => _action(
                                      context,
                                      () => queue.retry(task.id),
                                    ),
                                  ),
                                IconButton(
                                  tooltip:
                                      task.status == DownloadStatus.completed
                                      ? '删除 ${task.chapter.title} 的下载'
                                      : '取消 ${task.chapter.title} 的下载',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _action(
                                    context,
                                    () => queue.remove(task.id),
                                  ),
                                ),
                              ],
                            ),
                            onTap: task.status == DownloadStatus.completed
                                ? () => openDownloadedChapter(
                                    context,
                                    state,
                                    task,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
