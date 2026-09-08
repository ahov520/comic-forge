import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../services/source_service.dart';
import '../services/storage_bytes.dart';
import '../state/app_state.dart';
import '../state/download_queue.dart';
import 'cleanup_dialogs.dart';
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

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int? _downloadBytes;
  int? _cacheBytes;
  var _usageReady = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    if (!supportsStorageCleanup) return;
    final downloads = await state.downloads.usageBytes();
    final cache = await state.imageCache.usageBytes();
    if (!mounted) return;
    setState(() {
      _downloadBytes = downloads;
      _cacheBytes = cache;
      _usageReady = true;
    });
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
      await _refreshUsage();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请检查可用空间后重试')));
      }
    }
  }

  Future<void> _clearCompleted() async {
    final queue = state.downloads;
    final count = queue.tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    if (count == 0) return;
    final confirmed = await confirmCleanup(
      context,
      title: '清除已完成任务',
      message: '将删除 $count 话已完成章节的离线文件，并从列表移除。进行中和失败的任务会保留。',
    );
    if (!confirmed || !mounted) return;
    await _action(queue.clearCompleted);
  }

  Future<void> _clearFailed() async {
    final queue = state.downloads;
    final count = queue.tasks
        .where((task) => task.status == DownloadStatus.failed)
        .length;
    if (count == 0) return;
    final confirmed = await confirmCleanup(
      context,
      title: '清除失败任务',
      message: '将删除 $count 条失败任务及其不完整文件。已完成的离线章节不受影响。',
    );
    if (!confirmed || !mounted) return;
    await _action(queue.clearFailed);
  }

  Future<void> _clearImageCache() async {
    final confirmed = await confirmCleanup(
      context,
      title: '清除图片缓存',
      message: '将清除在线阅读的图片缓存以释放空间。已下载的离线章节不受影响。',
    );
    if (!confirmed || !mounted) return;
    await _action(() async {
      await state.imageCache.clearAll();
      SourceService.instance.clearChapterImageCache();
    });
  }

  Future<void> _clearBook(DownloadCatalog catalog) async {
    final queue = state.downloads;
    final count = queue.tasks
        .where((task) => task.bookKey == catalog.key)
        .length;
    if (count == 0) return;
    final name = catalog.book.name.trim().isEmpty ? '该漫画' : catalog.book.name;
    final confirmed = await confirmCleanup(
      context,
      title: '清除本书离线文件',
      message: '将删除「$name」的 $count 话离线下载，无法再离线阅读这些章节。进行中的任务也会取消。',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    final urls = queue.imageUrlsFor(catalog.key).toList();
    await _action(() async {
      await queue.removeBook(catalog.key);
      await state.imageCache.evictUrls(urls);
      SourceService.instance.clearChapterImageCache(
        sourceId: catalog.book.sourceId,
      );
    });
  }

  Future<void> _pickBookToClear() async {
    final queue = state.downloads;
    final catalogs = queue.catalogs;
    if (catalogs.isEmpty) return;
    final selected = await showModalBottomSheet<DownloadCatalog>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('按漫画清理离线文件')),
            for (final catalog in catalogs)
              ListTile(
                title: Text(
                  catalog.book.name.trim().isEmpty
                      ? '未命名漫画'
                      : catalog.book.name,
                ),
                subtitle: Text(
                  '${queue.tasks.where((task) => task.bookKey == catalog.key).length} 话',
                ),
                onTap: () => Navigator.pop(sheetCtx, catalog),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _clearBook(selected);
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
                    : () => _action(queue.retryFailed),
                icon: const Icon(Icons.refresh),
              ),
              if (supportsStorageCleanup)
                PopupMenuButton<String>(
                  tooltip: '清理存储',
                  onSelected: (value) {
                    switch (value) {
                      case 'completed':
                        _clearCompleted();
                      case 'failed':
                        _clearFailed();
                      case 'cache':
                        _clearImageCache();
                      case 'book':
                        _pickBookToClear();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'completed',
                      enabled: completed > 0,
                      child: const Text('清除已完成任务'),
                    ),
                    PopupMenuItem(
                      value: 'failed',
                      enabled: failed > 0,
                      child: const Text('清除失败任务'),
                    ),
                    const PopupMenuItem(value: 'cache', child: Text('清除图片缓存')),
                    if (queue.catalogs.isNotEmpty)
                      const PopupMenuItem(
                        value: 'book',
                        child: Text('按漫画清理离线文件'),
                      ),
                  ],
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
              ? Column(
                  children: [
                    if (supportsStorageCleanup && _usageReady)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            storageUsageLabel(
                              downloads: _downloadBytes,
                              cache: _cacheBytes,
                            ),
                          ),
                        ),
                      ),
                    const Expanded(
                      child: EmptyStateView(
                        icon: Icons.download_outlined,
                        title: '还没有下载任务',
                        message: '在漫画详情页选择章节，或选中未读章节批量下载。',
                      ),
                    ),
                  ],
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
                          if (supportsStorageCleanup && _usageReady) ...[
                            const SizedBox(height: 4),
                            Text(
                              storageUsageLabel(
                                downloads: _downloadBytes,
                                cache: _cacheBytes,
                              ),
                            ),
                          ],
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
                                    onPressed: () =>
                                        _action(() => queue.retry(task.id)),
                                  ),
                                IconButton(
                                  tooltip:
                                      task.status == DownloadStatus.completed
                                      ? '删除 ${task.chapter.title} 的下载'
                                      : '取消 ${task.chapter.title} 的下载',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _action(() => queue.remove(task.id)),
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
