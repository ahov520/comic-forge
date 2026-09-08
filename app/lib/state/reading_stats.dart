import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

class ReadingStatsSummary {
  const ReadingStatsSummary({
    this.duration = Duration.zero,
    this.bookCount = 0,
    this.chapterCount = 0,
    this.activeDays = 0,
  });

  final Duration duration;
  final int bookCount;
  final int chapterCount;
  final int activeDays;
}

/// 单本累计统计快照；同名漫画按来源和链接区分。
class ComicReadingStats {
  const ComicReadingStats({
    required this.sourceId,
    required this.bookUrl,
    required this.name,
    required this.duration,
    required this.chapterCount,
    required this.sessionCount,
    required this.lastReadAt,
  });

  final String? sourceId;
  final String bookUrl;
  final String name;
  final Duration duration;
  final int chapterCount;
  final int sessionCount;
  final DateTime lastReadAt;

  String get key => _bookKey(sourceId, bookUrl);
}

class _ComicReadingRecord {
  _ComicReadingRecord({
    required this.sourceId,
    required this.bookUrl,
    required this.name,
    required this.lastReadAt,
  });

  final String? sourceId;
  final String bookUrl;
  String name;
  DateTime lastReadAt;
  int milliseconds = 0;
  int sessionCount = 0;
  final Set<String> chapters = {};

  ComicReadingStats get summary => ComicReadingStats(
    sourceId: sourceId,
    bookUrl: bookUrl,
    name: name,
    duration: Duration(milliseconds: milliseconds),
    chapterCount: chapters.length,
    sessionCount: sessionCount,
    lastReadAt: lastReadAt,
  );

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'bookUrl': bookUrl,
    'name': name,
    'milliseconds': milliseconds,
    'chapters': chapters.toList(),
    'sessionCount': sessionCount,
    'lastReadAt': lastReadAt.millisecondsSinceEpoch,
  };

  static _ComicReadingRecord? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final sourceId = value['sourceId'];
    final bookUrl = value['bookUrl'];
    final name = value['name'];
    final milliseconds = value['milliseconds'];
    final chapters = value['chapters'];
    final sessionCount = value['sessionCount'];
    final lastReadAt = value['lastReadAt'];
    if ((sourceId != null && sourceId is! String) ||
        bookUrl is! String ||
        bookUrl.isEmpty ||
        name is! String ||
        milliseconds is! int ||
        milliseconds < 0 ||
        chapters is! List ||
        sessionCount is! int ||
        sessionCount < 0 ||
        lastReadAt is! int) {
      return null;
    }
    try {
      final record =
          _ComicReadingRecord(
              sourceId: sourceId as String?,
              bookUrl: bookUrl,
              name: name,
              lastReadAt: DateTime.fromMillisecondsSinceEpoch(lastReadAt),
            )
            ..milliseconds = milliseconds
            ..sessionCount = sessionCount
            ..chapters.addAll(
              chapters.whereType<String>().where((url) => url.isNotEmpty),
            );
      return record.chapters.isEmpty ? null : record;
    } on ArgumentError {
      return null;
    }
  }
}

class _ReadingDay {
  int milliseconds = 0;
  final Set<String> books = {};
  final Set<String> chapters = {};

  Map<String, dynamic> toJson() => {
    'milliseconds': milliseconds,
    'books': books.toList(),
    'chapters': chapters.toList(),
  };
}

/// 按本地自然日保存阅读时长和去重标识，独立于历史、书架和阅读进度。
class ReadingStats extends ChangeNotifier {
  ReadingStats({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _key = 'cf.readingStats';
  final DateTime Function() _now;
  final Map<String, _ReadingDay> _days = {};
  final Map<String, _ComicReadingRecord> _comics = {};
  bool _disposed = false;

  DateTime get now => _now();
  ReadingStatsSummary get today => forDay(now);
  ReadingStatsSummary get total => _summarize(_days.values);

  /// 按最近阅读排序；旧版每日总量无法分配给单本，不在此推算。
  List<ComicReadingStats> get comics =>
      _comics.values.map((record) => record.summary).toList()..sort((a, b) {
        final byTime = b.lastReadAt.compareTo(a.lastReadAt);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });

  ComicReadingStats? forBook(Book book) =>
      _comics[_bookKey(book.sourceId, book.bookUrl)]?.summary;

  ReadingStatsSummary forDay(DateTime date) {
    final day = _days[_dayKey(date.toLocal())];
    return _summarize(day == null ? const [] : [day]);
  }

  List<({DateTime date, ReadingStatsSummary summary})> get recentDays {
    final current = now.toLocal();
    return List.generate(7, (index) {
      final date = DateTime(current.year, current.month, current.day - index);
      return (date: date, summary: forDay(date));
    });
  }

  ReadingStatsSummary _summarize(Iterable<_ReadingDay> days) {
    var milliseconds = 0;
    var activeDays = 0;
    final books = <String>{};
    final chapters = <String>{};
    for (final day in days) {
      milliseconds += day.milliseconds;
      activeDays++;
      books.addAll(day.books);
      chapters.addAll(day.chapters);
    }
    return ReadingStatsSummary(
      duration: Duration(milliseconds: milliseconds),
      bookCount: books.length,
      chapterCount: chapters.length,
      activeDays: activeDays,
    );
  }

  Future<void> load() async {
    _days.clear();
    _comics.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_key);
    if (raw is! String) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic>) return;
      for (final entry in saved.entries) {
        final date = DateTime.tryParse(entry.key);
        final value = entry.value;
        if (date == null ||
            _dayKey(date) != entry.key ||
            value is! Map<String, dynamic>) {
          continue;
        }
        final milliseconds = value['milliseconds'];
        final books = value['books'];
        final chapters = value['chapters'];
        if (milliseconds is! int ||
            milliseconds < 0 ||
            books is! List ||
            chapters is! List) {
          continue;
        }
        final day = _ReadingDay()
          ..milliseconds = milliseconds
          ..books.addAll(
            books.whereType<String>().where((key) => key.isNotEmpty),
          )
          ..chapters.addAll(
            chapters.whereType<String>().where((key) => key.isNotEmpty),
          );
        if (day.books.isNotEmpty && day.chapters.isNotEmpty) {
          _days[entry.key] = day;
        }
      }
      final comics = saved['comics'];
      if (comics is Map<String, dynamic>) {
        for (final entry in comics.entries) {
          final record = _ComicReadingRecord.fromJson(entry.value);
          if (record != null &&
              _bookKey(record.sourceId, record.bookUrl) == entry.key) {
            _comics[entry.key] = record;
          }
        }
      }
    } on FormatException {
      // 无法恢复统计时从零开始，不从旧阅读进度推测时长或话数。
    }
  }

  /// [from] 到 [to] 必须是阅读器实际可见的时间段；跨午夜自动拆分。
  /// 一次进入章节仅首段设置 [startsSession]，暂停续读和保存检查点不重复计次。
  Future<void> record(
    Book book,
    Chapter chapter, {
    required DateTime from,
    required DateTime to,
    bool startsSession = true,
  }) async {
    if (_disposed ||
        book.bookUrl.isEmpty ||
        chapter.url.isEmpty ||
        to.isBefore(from)) {
      return;
    }
    final bookKey = _bookKey(book.sourceId, book.bookUrl);
    final chapterKey = jsonEncode([
      book.sourceId ?? '',
      book.bookUrl,
      chapter.url,
    ]);
    var cursor = from.toLocal();
    final end = to.toLocal();
    var changed = false;
    var elapsed = 0;
    do {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final until = end.isBefore(midnight) ? end : midnight;
      final milliseconds = until.difference(cursor).inMilliseconds;
      elapsed += milliseconds;
      final day = _days.putIfAbsent(_dayKey(cursor), _ReadingDay.new);
      final addedBook = day.books.add(bookKey);
      final addedChapter = day.chapters.add(chapterKey);
      day.milliseconds += milliseconds;
      changed = changed || addedBook || addedChapter || milliseconds > 0;
      cursor = until;
    } while (cursor.isBefore(end));
    final comic = _comics.putIfAbsent(bookKey, () {
      changed = true;
      return _ComicReadingRecord(
        sourceId: book.sourceId,
        bookUrl: book.bookUrl,
        name: book.name,
        lastReadAt: end,
      );
    });
    comic.milliseconds += elapsed;
    if (comic.chapters.add(chapter.url)) changed = true;
    if (startsSession) {
      comic.sessionCount++;
      changed = true;
    }
    if (!end.isBefore(comic.lastReadAt)) {
      if (end != comic.lastReadAt) {
        comic.lastReadAt = end;
        changed = true;
      }
      if (book.name.trim().isNotEmpty && book.name != comic.name) {
        comic.name = book.name;
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 写入前取最新内存态，切话/暂停同时落盘也不会写回旧快照。
    await prefs.setStringSafe(
      _key,
      jsonEncode({
        ..._days.map((key, day) => MapEntry(key, day.toJson())),
        'comics': _comics.map((key, record) => MapEntry(key, record.toJson())),
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _bookKey(String? sourceId, String bookUrl) =>
    jsonEncode([sourceId ?? '', bookUrl]);

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String formatReadingDuration(Duration duration) {
  if (duration <= Duration.zero) return '0 分钟';
  if (duration.inMinutes == 0) return '不足 1 分钟';
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours == 0) return '$minutes 分钟';
  return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
}
