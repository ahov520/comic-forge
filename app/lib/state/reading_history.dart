import 'dart:convert';

import 'package:engine/engine.dart';

/// 每本漫画保留最近一次阅读快照，独立于书架、详情缓存和角标清除状态。
class ReadingHistoryEntry {
  ReadingHistoryEntry({
    required this.book,
    required this.chapter,
    required this.chapterIndex,
    required this.chapterCount,
    required this.at,
  });

  final Book book;
  final Chapter chapter;
  final int chapterIndex;
  final int chapterCount;
  final int at;

  String get key => jsonEncode([book.sourceId ?? '', book.bookUrl]);

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'chapter': chapter.toJson(),
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    'at': at,
  };

  factory ReadingHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ReadingHistoryEntry(
        book: Book.fromJson(json['book'] as Map<String, dynamic>),
        chapter: Chapter.fromJson(json['chapter'] as Map<String, dynamic>),
        chapterIndex: json['chapterIndex'] as int,
        chapterCount: json['chapterCount'] as int,
        at: json['at'] as int,
      );
}

String readingHistoryDay(int at, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  final date = DateTime.fromMillisecondsSinceEpoch(at).toLocal();
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return '今天';
  if (day == yesterday) return '昨天';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String readingHistoryTime(int at) {
  final date = DateTime.fromMillisecondsSinceEpoch(at).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// 书架「继续阅读」条展示的最近记录数。
const int continueReadingLimit = 8;

List<ReadingHistoryEntry> continueReadingEntries(
  Iterable<ReadingHistoryEntry> history, {
  int limit = continueReadingLimit,
}) {
  if (limit <= 0) return const [];
  return history.take(limit).toList(growable: false);
}

String readingHistoryBookName(ReadingHistoryEntry entry) {
  final name = entry.book.name.trim();
  return name.isEmpty ? '未命名漫画' : name;
}

String readingHistoryChapterName(ReadingHistoryEntry entry) {
  final title = entry.chapter.title.trim();
  return title.isEmpty ? '第 ${entry.chapterIndex + 1} 话' : title;
}

/// 封面旁的章节/进度提示：有目录总数时带上 `当前/总话数`。
String continueReadingHint(ReadingHistoryEntry entry) {
  final chapter = readingHistoryChapterName(entry);
  if (entry.chapterCount > 0) {
    return '$chapter · ${entry.chapterIndex + 1}/${entry.chapterCount}';
  }
  return chapter;
}
