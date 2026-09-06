import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';
import 'book_detail_screen.dart';
import 'reader_screen.dart';

/// 阅读器前的统一封面组件。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.url, this.width = 96, this.height = 128});

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
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
      ),
    );
  }
}

/// 搜索/探索结果条目。
class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.book, required this.state});

  final Book book;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: BookCover(url: book.coverUrl, width: 56, height: 76),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (book.author.isNotEmpty) book.author,
          if (book.kind.isNotEmpty) book.kind,
          if (book.lastChapter.isNotEmpty) '更新: ${book.lastChapter}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.outline),
      ),
      trailing: IconButton(
        icon: Icon(
          state.inShelf(book) ? Icons.favorite : Icons.favorite_border,
          color: state.inShelf(book) ? scheme.primary : null,
        ),
        onPressed: () => state.toggleShelf(book),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookDetailScreen(book: book, appState: state),
      )),
    );
  }
}

/// 简易错误视图。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text('加载失败：$error', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 阅读器入口：详情页章节 → 图片流（带章节导航与进度记忆）。
void openReader(
    BuildContext context, SourceRuntime runtime, Book book,
    List<Chapter> chapters, int index, AppState? appState) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ReaderScreen(
        runtime: runtime,
        book: book,
        chapters: chapters,
        initialIndex: index,
        appState: appState),
  ));
}
