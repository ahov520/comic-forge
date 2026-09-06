import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';
import 'book_detail_screen.dart';
import 'reader_screen.dart';
import 'skeleton.dart';

/// 阅读器前的统一封面组件。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.url,
    this.width = 96,
    this.height = 128,
  });

  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: url.isEmpty
            ? Icon(Icons.menu_book_outlined, color: scheme.outline)
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: width,
                height: height,
                // 加载中用呼吸骨架，替代死灰块
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : SkeletonBox(width: width, height: height),
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
      ),
    );
  }
}

/// 搜索/探索结果条目。
class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.state,
    this.sourceLabel,
  });

  final Book book;
  final AppState state;

  /// 来源标签（聚合搜索结果显示用；null 不显示）。
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metadata = [
      if (book.author.trim().isNotEmpty) book.author.trim(),
      if (book.kind.trim().isNotEmpty) book.kind.trim(),
    ].join(' · ');
    final source = sourceLabel?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(book: book, appState: state),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(url: book.coverUrl, width: 64, height: 96),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: state,
                          builder: (context, _) {
                            final saved = state.inShelf(book);
                            return IconButton(
                              tooltip: saved ? '移出书架' : '加入书架',
                              isSelected: saved,
                              onPressed: () => state.toggleShelf(book),
                              icon: AnimatedSwitcher(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                child: Icon(
                                  saved
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  key: ValueKey(saved),
                                  color: saved
                                      ? scheme.primary
                                      : scheme.outline,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (metadata.isNotEmpty)
                      Text(
                        metadata,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (book.lastChapter.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '更新至 ${book.lastChapter.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (source.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Tooltip(
                        message: '来源：$source',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.public,
                                size: 14,
                                color: scheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 带下一步指引的空状态；窄屏、键盘展开或大字号时仍可滚动。
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 简易错误视图。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.cloud_off_outlined,
  });
  final Object? error;
  final VoidCallback? onRetry;

  /// 附加动作（如「启用该源并重试」）。
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(
              '加载失败：$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 阅读器入口：详情页章节 → 图片流（带章节导航与进度记忆）。
void openReader(
  BuildContext context,
  SourceRuntime runtime,
  Book book,
  List<Chapter> chapters,
  int index,
  AppState? appState,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReaderScreen(
        runtime: runtime,
        book: book,
        chapters: chapters,
        initialIndex: index,
        appState: appState,
      ),
    ),
  );
}
