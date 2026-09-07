import 'dart:convert';

import 'package:engine/engine.dart';

/// 书架保留目录链接，即使详情的 LRU 缓存被淘汰仍能比较阅读进度。
class ShelfChapters {
  ShelfChapters({
    required this.sourceId,
    required this.urls,
    required this.latestTitle,
  });

  factory ShelfChapters.fromDetail(Book book, List<Chapter> chapters) =>
      ShelfChapters(
        sourceId: book.sourceId ?? '',
        urls: List.unmodifiable(chapters.map((chapter) => chapter.url)),
        latestTitle: chapters.last.title,
      );

  final String sourceId;
  final List<String> urls;
  final String latestTitle;

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'urls': urls,
    'latestTitle': latestTitle,
  };

  static ShelfChapters fromJson(Map<String, dynamic> json) => ShelfChapters(
    sourceId: json['sourceId'] as String? ?? '',
    urls: List.unmodifiable((json['urls'] as List).cast<String>()),
    latestTitle: json['latestTitle'] as String? ?? '',
  );
}

class ShelfUpdateBadge {
  const ShelfUpdateBadge({
    required this.token,
    required this.label,
    required this.latestTitle,
    this.unreadCount,
  });

  final String token;
  final String label;
  final String latestTitle;
  final int? unreadCount;
}

String normalizeChapterTitle(String title) => title
    .trim()
    .replaceFirst(RegExp(r'^(?:更新至?|最新(?:章节)?)[：:\s]*'), '')
    .replaceAll(RegExp(r'\s+'), '');

String shelfUpdateToken(String sourceId, String latestUrl, String title) =>
    jsonEncode([sourceId, latestUrl, normalizeChapterTitle(title)]);

typedef ShelfRefreshResult = ({int checked, int failed, int skipped});
