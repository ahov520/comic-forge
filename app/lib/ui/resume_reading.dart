import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/download_queue.dart';
import '../state/reading_history.dart';
import 'book_detail_screen.dart';
import 'downloads_screen.dart';
import 'widgets.dart';

void openReadingHistoryDetail(
  BuildContext context,
  AppState state,
  ReadingHistoryEntry entry,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BookDetailScreen(book: entry.book, appState: state),
    ),
  );
}

/// 用阅读历史快照续读：已下载话直接打开，否则走缓存或拉取目录。
Future<void> resumeReadingHistory({
  required BuildContext context,
  required AppState state,
  required ReadingHistoryEntry entry,
  required bool Function() isCurrent,
  required VoidCallback openDetail,
}) async {
  try {
    final downloaded = state.downloads.taskFor(entry.book, entry.chapter);
    if (downloaded?.status == DownloadStatus.completed) {
      if (!isCurrent()) return;
      openDownloadedChapter(context, state, downloaded!);
      return;
    }
    final source = state.sources
        .where((source) => source.id == entry.book.sourceId && source.enabled)
        .firstOrNull;
    if (source == null) {
      if (isCurrent()) openDetail();
      return;
    }
    final runtime = SourceService.instance.runtimeFor(source);
    final cached = state.detailCacheFor(entry.book.bookUrl);
    Book book;
    List<Chapter> chapters;
    if (cached != null &&
        cached.book.sourceId == entry.book.sourceId &&
        cached.chapters.isNotEmpty) {
      book = Book.fromJson({
        ...entry.book.toJson(),
        ...cached.book.toJson(),
        if (cached.book.name.trim().isEmpty) 'name': entry.book.name,
      });
      chapters = cached.chapters;
    } else {
      final fresh = await runtime
          .detail(entry.book.bookUrl)
          .timeout(const Duration(seconds: 20));
      if (!isCurrent()) return;
      if (!state.sources.any((s) => identical(s, source) && s.enabled)) {
        openDetail();
        return;
      }
      book = Book.fromJson({
        ...entry.book.toJson(),
        ...fresh.$1.toJson(),
        if (fresh.$1.name.trim().isEmpty) 'name': entry.book.name,
      });
      chapters = fresh.$2;
      if (chapters.isEmpty) throw StateError('暂无章节');
      await state.saveDetailCache(book, chapters);
    }
    if (!isCurrent()) return;
    final savedIndex = chapters.indexWhere(
      (chapter) => chapter.url == entry.chapter.url,
    );
    final index = savedIndex < 0
        ? entry.chapterIndex.clamp(0, chapters.length - 1)
        : savedIndex;
    openReader(context, runtime, book, chapters, index, state);
  } catch (_) {
    if (!isCurrent()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('暂时无法续读，可打开详情重试或换源'),
        action: SnackBarAction(label: '打开详情', onPressed: openDetail),
      ),
    );
  }
}
