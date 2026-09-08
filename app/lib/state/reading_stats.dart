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
  bool _disposed = false;

  DateTime get now => _now();
  ReadingStatsSummary get today => forDay(now);
  ReadingStatsSummary get total => _summarize(_days.values);

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
    } on FormatException {
      // 无法恢复统计时从零开始，不从旧阅读进度推测时长或话数。
    }
  }

  /// [from] 到 [to] 必须是阅读器实际可见的时间段；跨午夜自动拆分。
  Future<void> record(
    Book book,
    Chapter chapter, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (_disposed ||
        book.bookUrl.isEmpty ||
        chapter.url.isEmpty ||
        to.isBefore(from)) {
      return;
    }
    final bookKey = jsonEncode([book.sourceId ?? '', book.bookUrl]);
    final chapterKey = jsonEncode([
      book.sourceId ?? '',
      book.bookUrl,
      chapter.url,
    ]);
    var cursor = from.toLocal();
    final end = to.toLocal();
    var changed = false;
    do {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final until = end.isBefore(midnight) ? end : midnight;
      final milliseconds = until.difference(cursor).inMilliseconds;
      final day = _days.putIfAbsent(_dayKey(cursor), _ReadingDay.new);
      final addedBook = day.books.add(bookKey);
      final addedChapter = day.chapters.add(chapterKey);
      day.milliseconds += milliseconds;
      changed = changed || addedBook || addedChapter || milliseconds > 0;
      cursor = until;
    } while (cursor.isBefore(end));
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 写入前取最新内存态，切话/暂停同时落盘也不会写回旧快照。
    await prefs.setStringSafe(
      _key,
      jsonEncode(_days.map((key, day) => MapEntry(key, day.toJson()))),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

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
