import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'state/app_state.dart';
import 'state/chapter_bookmarks.dart';
import 'state/reading_history.dart';

/// 本地/WebDAV 共用的导入策略。
enum BackupImportMode { merge, overwrite }

typedef BackupImportCounts = ({
  int sources,
  int shelf,
  int progress,
  int repos,
  int history,
  int bookmarks,
  int settings,
});

/// 已解析的备份载荷。解析失败不会改动 AppState。
class BackupPayload {
  BackupPayload({
    required this.version,
    required this.sources,
    required this.shelf,
    required this.progress,
    required this.repos,
    this.history,
    this.bookmarks,
    this.settings,
    this.shelfGroups,
    this.readingStats,
    this.readerPages,
    this.scrollOffsets,
  });

  final int version;
  final List<ComicSource> sources;
  final List<Book> shelf;
  final Map<String, ReadingProgress> progress;
  final List<String> repos;
  final List<ReadingHistoryEntry>? history;
  final List<ChapterBookmark>? bookmarks;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? shelfGroups;
  final Map<String, dynamic>? readingStats;
  final Map<String, int>? readerPages;
  final Map<String, dynamic>? scrollOffsets;

  factory BackupPayload.fromJson(Map<String, dynamic> json) {
    return BackupPayload(
      version: json['version'] is int ? json['version'] as int : 1,
      sources: _maps(
        json['sources'],
      ).map(_trySource).whereType<ComicSource>().toList(),
      shelf: _maps(json['shelf']).map(_tryBook).whereType<Book>().toList(),
      progress: _progress(json['progress']),
      repos: (json['repos'] as List? ?? [])
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList(),
      history: json.containsKey('history')
          ? _maps(
              json['history'],
            ).map(_tryHistory).whereType<ReadingHistoryEntry>().toList()
          : null,
      bookmarks: json.containsKey('bookmarks')
          ? _maps(
              json['bookmarks'],
            ).map(_tryBookmark).whereType<ChapterBookmark>().toList()
          : null,
      settings: json['settings'] is Map<String, dynamic>
          ? json['settings'] as Map<String, dynamic>
          : null,
      shelfGroups: json['shelfGroups'] is Map<String, dynamic>
          ? json['shelfGroups'] as Map<String, dynamic>
          : null,
      readingStats: json['readingStats'] is Map<String, dynamic>
          ? json['readingStats'] as Map<String, dynamic>
          : null,
      readerPages: _readerPages(json['readerPages']),
      scrollOffsets: json['scrollOffsets'] is Map<String, dynamic>
          ? json['scrollOffsets'] as Map<String, dynamic>
          : null,
    );
  }

  static List<Map<String, dynamic>> _maps(Object? raw) =>
      (raw as List? ?? []).whereType<Map<String, dynamic>>().toList();

  static ComicSource? _trySource(Map<String, dynamic> json) {
    try {
      final source = ComicSource.fromJson(json);
      return source.id.isEmpty && source.url.isEmpty ? null : source;
    } catch (_) {
      return null;
    }
  }

  static Book? _tryBook(Map<String, dynamic> json) {
    try {
      final book = Book.fromJson(json);
      return book.bookUrl.isEmpty ? null : book;
    } catch (_) {
      return null;
    }
  }

  static Map<String, ReadingProgress> _progress(Object? raw) {
    if (raw is! Map<String, dynamic>) return {};
    final out = <String, ReadingProgress>{};
    raw.forEach((key, value) {
      if (key.isEmpty || value is! Map<String, dynamic>) return;
      try {
        final reading = ReadingProgress.fromJson(value);
        if (reading.bookUrl.isEmpty) return;
        out[key] = reading;
      } catch (_) {}
    });
    return out;
  }

  static ReadingHistoryEntry? _tryHistory(Map<String, dynamic> json) {
    try {
      final entry = ReadingHistoryEntry.fromJson(json);
      if (entry.book.bookUrl.isEmpty ||
          entry.chapterIndex < 0 ||
          entry.chapterCount < 0 ||
          entry.at < 0) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  static ChapterBookmark? _tryBookmark(Map<String, dynamic> json) {
    try {
      final entry = ChapterBookmark.fromJson(json);
      if (entry.book.bookUrl.isEmpty ||
          entry.chapter.url.isEmpty ||
          entry.chapterIndex < 0 ||
          entry.at < 0) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  static Map<String, int>? _readerPages(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && key.isNotEmpty && value is int && value >= 0) {
        out[key] = value;
      }
    });
    return out;
  }
}

/// 备份/恢复载荷（书架 + 源库 + 阅读进度 + 订阅仓库 + 历史/书签/设置）。
class BackupService {
  BackupService._();

  static const formatVersion = 2;
  static const defaultRemotePath = '/comic-forge/backup.json';
  static const formatError = '备份文件格式不正确（需要 comic-forge 导出的 JSON）';

  /// Android 本地导出/导入；测试可覆盖平台。
  static bool get supportsLocalExchange =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String suggestedFileName({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    return 'comic-forge-backup-$y$m$d.json';
  }

  /// 从 AppState 导出 JSON 文本。不含离线图片与 WebDAV 密码。
  static String exportJson(AppState st) {
    return jsonEncode({
      'app': 'comic-forge',
      'version': formatVersion,
      'at': DateTime.now().millisecondsSinceEpoch,
      'sources': st.sources.map((s) => s.toJson()).toList(),
      'shelf': st.shelf.map((b) => b.toJson()).toList(),
      'progress': st.progress.map((k, v) => MapEntry(k, v.toJson())),
      'repos': st.repos,
      'history': st.readingHistory.map((e) => e.toJson()).toList(),
      'bookmarks': st.chapterBookmarks.map((e) => e.toJson()).toList(),
      'settings': {
        'darkMode': st.darkMode,
        'readerBrightness': st.readerBrightness,
        'readerMode': st.readerMode,
        'readerVolumeKeys': st.readerVolumeKeys,
        'shelfSort': st.shelfSort.id,
        'shelfUpdateEnabled': st.shelfUpdateSchedule.enabled,
        'shelfUpdateIntervalHours': st.shelfUpdateSchedule.interval.hours,
        'updateNotificationsEnabled': st.updateNotifications.enabled,
        'adBlock': st.adBlock?.toJson(),
        'blockedDomains': st.blockedDomains,
        'searchFilters': st.searchFilters.toJson(),
        'searchHistory': st.searchHistory,
      },
      'shelfGroups': st.shelfGroups.toBackupJson(),
      'readingStats': st.readingStats.toBackupJson(),
      'readerPages': st.readerPages,
      'scrollOffsets': st.scrollOffsets.map(
        (k, v) => MapEntry(k, {
          'v': v.offset,
          'at': v.at,
          if (v.width != null) 'w': v.width,
          if (v.width != null && v.topInset != 0) 'top': v.topInset,
        }),
      ),
    });
  }

  /// 解析备份 JSON；坏格式返回 null。
  static Map<String, dynamic>? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map<String, dynamic> && j['app'] == 'comic-forge') return j;
    } on FormatException {
      return null;
    }
    return null;
  }

  static BackupPayload parsePayload(String text) {
    final json = tryParse(text);
    if (json == null) throw const FormatException(formatError);
    try {
      return BackupPayload.fromJson(json);
    } catch (_) {
      throw const FormatException(formatError);
    }
  }

  /// 导入到 AppState。[mode] 为覆盖时替换对应集合；缺省字段保持本地。
  static Future<BackupImportCounts> importJson(
    AppState st,
    String text, {
    BackupImportMode mode = BackupImportMode.merge,
  }) async {
    return st.applyBackup(parsePayload(text), mode: mode);
  }

  /// 备份到 WebDAV：先逐级建目录再上传。[client] 可注入（测试用）。
  static Future<void> backupToWebDav({
    required AppState st,
    required String baseUrl,
    String username = '',
    String password = '',
    String remotePath = defaultRemotePath,
    http.Client? client,
  }) async {
    final dav = WebDavClient(
      baseUrl: baseUrl,
      username: username,
      password: password,
      client: client,
    );
    final dir = remotePath.substring(0, remotePath.lastIndexOf('/'));
    if (dir.isNotEmpty) await dav.mkdirp(dir);
    await dav.putBytes(remotePath, utf8.encode(exportJson(st)));
  }

  /// 从 WebDAV 恢复（合并语义）。返回各类新增数量。
  static Future<BackupImportCounts> restoreFromWebDav({
    required AppState st,
    required String baseUrl,
    String username = '',
    String password = '',
    String remotePath = defaultRemotePath,
    http.Client? client,
  }) async {
    final dav = WebDavClient(
      baseUrl: baseUrl,
      username: username,
      password: password,
      client: client,
    );
    final text = utf8.decode(await dav.getBytes(remotePath));
    return importJson(st, text);
  }
}
