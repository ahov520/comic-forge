import 'dart:convert';

import 'package:engine/engine.dart';

/// 按漫画+章节保存的书签。同一话只保留一条，独立于阅读进度和历史。
class ChapterBookmark {
  ChapterBookmark({
    required this.book,
    required this.chapter,
    required this.chapterIndex,
    required this.at,
  });

  final Book book;
  final Chapter chapter;
  final int chapterIndex;
  final int at;

  String get bookKey => bookKeyFor(book);

  String get key => keyFor(book, chapter);

  String get displayTitle {
    final title = chapter.title.trim();
    return title.isEmpty ? '第 ${chapterIndex + 1} 话' : title;
  }

  static String bookKeyFor(Book book) =>
      jsonEncode([book.sourceId ?? '', book.bookUrl]);

  static String keyFor(Book book, Chapter chapter) =>
      jsonEncode([book.sourceId ?? '', book.bookUrl, chapter.url]);

  /// 优先按章节链接对齐当前目录；找不到时回退到记下的序号。
  int? indexIn(List<Chapter> chapters) {
    if (chapters.isEmpty) return null;
    if (chapter.url.isNotEmpty) {
      final byUrl = chapters.indexWhere((item) => item.url == chapter.url);
      if (byUrl >= 0) return byUrl;
    }
    if (chapterIndex >= 0 && chapterIndex < chapters.length) {
      return chapterIndex;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'chapter': chapter.toJson(),
    'chapterIndex': chapterIndex,
    'at': at,
  };

  factory ChapterBookmark.fromJson(Map<String, dynamic> json) =>
      ChapterBookmark(
        book: Book.fromJson(json['book'] as Map<String, dynamic>),
        chapter: Chapter.fromJson(json['chapter'] as Map<String, dynamic>),
        chapterIndex: json['chapterIndex'] as int,
        at: json['at'] as int,
      );
}
