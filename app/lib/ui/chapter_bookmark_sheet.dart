import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/chapter_bookmarks.dart';
import '../state/reading_history.dart';
import 'widgets.dart';

/// 某本漫画的章节书签列表：点选跳转，可单独移除。
class ChapterBookmarkSheet extends StatelessWidget {
  const ChapterBookmarkSheet({
    super.key,
    required this.state,
    required this.book,
    required this.onPick,
    this.currentChapterUrl,
  });

  final AppState state;
  final Book book;
  final ValueChanged<ChapterBookmark> onPick;
  final String? currentChapterUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final bookmarks = state.bookmarksFor(book);
        return Material(
          color: Theme.of(context).bottomSheetTheme.backgroundColor ??
              scheme.surface,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      header: true,
                      child: Text(
                        bookmarks.isEmpty
                            ? '书签'
                            : '书签 · ${bookmarks.length} 话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                if (bookmarks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: EmptyStateView(
                      icon: Icons.bookmark_border,
                      title: '还没有书签',
                      message: '阅读时点顶栏书签，即可把当前话记下来。',
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: bookmarks.length,
                      itemBuilder: (context, index) {
                        final bookmark = bookmarks[index];
                        final current =
                            currentChapterUrl != null &&
                            bookmark.chapter.url == currentChapterUrl;
                        return ListTile(
                          selected: current,
                          leading: Icon(
                            current
                                ? Icons.bookmark
                                : Icons.bookmark_outline,
                          ),
                          title: Text(
                            bookmark.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '第 ${bookmark.chapterIndex + 1} 话 · '
                            '${readingHistoryDay(bookmark.at)} '
                            '${readingHistoryTime(bookmark.at)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '移除书签',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                state.removeChapterBookmark(bookmark.key),
                          ),
                          onTap: () => onPick(bookmark),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
