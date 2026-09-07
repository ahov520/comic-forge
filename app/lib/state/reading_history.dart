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
