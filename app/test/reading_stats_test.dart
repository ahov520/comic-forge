import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_session.dart';
import 'package:comic_forge/state/reading_stats.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late ReadingStats stats;
  final book = Book(name: '统计漫画', sourceId: 'source-a', bookUrl: '/book');
  final first = Chapter(title: '第一话', url: '/chapter/1');
  final second = Chapter(title: '第二话', url: '/chapter/2');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 8, 12);
    stats = ReadingStats(now: () => now);
  });
  tearDown(() => stats.dispose());

  test('重复阅读累加时长，漫画与章节按来源去重，跨天仍保留累计去重', () async {
    Future<void> read(Book b, Chapter c) => stats.record(
      b,
      c,
      from: now.subtract(const Duration(minutes: 1)),
      to: now,
    );
    await read(book, first);
    await read(book, first);
    await read(book, second);
    expect(stats.today.duration, const Duration(minutes: 3));
    expect(stats.today.bookCount, 1);
    expect(stats.today.chapterCount, 2);
    final otherSource = Book.fromJson({
      ...book.toJson(),
      'sourceId': 'source-b',
    });
    await read(otherSource, first);
    expect(stats.total.bookCount, 2);
    expect(stats.total.chapterCount, 3);
    now = now.add(const Duration(days: 1));
    await read(book, first);
    expect(stats.today.bookCount, 1);
    expect(stats.today.chapterCount, 1);
    expect(stats.total.bookCount, 2);
    expect(stats.total.chapterCount, 3);
    expect(stats.total.duration, const Duration(minutes: 5));
    expect(stats.total.activeDays, 2);
  });

  test('跨年午夜按自然日拆分时长，近七日补齐无阅读日期', () async {
    now = DateTime(2027, 1, 1, 0, 0, 30);
    await stats.record(
      book,
      first,
      from: DateTime(2026, 12, 31, 23, 59, 30),
      to: now,
    );
    expect(stats.today.duration, const Duration(seconds: 30));
    expect(
      stats.forDay(DateTime(2026, 12, 31)).duration,
      const Duration(seconds: 30),
    );
    expect(stats.total.duration, const Duration(minutes: 1));
    expect(stats.total.bookCount, 1);
    expect(stats.total.chapterCount, 1);
    expect(stats.total.activeDays, 2);
    final days = stats.recentDays;
    expect(days, hasLength(7));
    expect(days.first.date, DateTime(2027, 1, 1));
    expect(days.last.date, DateTime(2026, 12, 26));
    expect(days.last.summary.duration, Duration.zero);
    expect(days.last.summary.chapterCount, 0);
  });

  test('并发保存采用最新快照，重启恢复时长和去重信息', () async {
    await Future.wait([
      stats.record(
        book,
        first,
        from: now.subtract(const Duration(seconds: 20)),
        to: now,
      ),
      stats.record(
        book,
        second,
        from: now.subtract(const Duration(seconds: 30)),
        to: now,
      ),
    ]);
    final restored = ReadingStats(now: () => now);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.total.duration, const Duration(seconds: 50));
    expect(restored.total.chapterCount, 2);
    expect(restored.total.bookCount, 1);
    await restored.record(book, first, from: now, to: now);
    expect(restored.total.chapterCount, 2);
  });

  test('会话只计入已加载且可见的时间段，暂停、切话和重复保存不重复计时', () async {
    final session = ReadingSession(stats);
    await session.setActive(true);
    now = now.add(const Duration(minutes: 10));
    expect(stats.total.chapterCount, 0);
    await session.openChapter(book, first);
    now = now.add(const Duration(seconds: 15));
    await session.checkpoint();
    await session.checkpoint();
    now = now.add(const Duration(seconds: 10));
    await session.setActive(false);
    now = now.add(const Duration(hours: 2));
    await session.openChapter(book, second);
    expect(stats.total.duration, const Duration(seconds: 25));
    expect(stats.total.chapterCount, 1);
    await session.setActive(true);
    now = now.add(const Duration(seconds: 30));
    await session.closeChapter();
    await session.closeChapter();
    expect(stats.total.duration, const Duration(seconds: 55));
    expect(stats.total.chapterCount, 2);
  });

  test('时钟回拨、空链接和反向时间段不会产生负时长或虚构记录', () async {
    await stats.record(Book(), first, from: now, to: now);
    await stats.record(book, Chapter(), from: now, to: now);
    await stats.record(
      book,
      first,
      from: now,
      to: now.subtract(const Duration(seconds: 1)),
    );
    expect(stats.total.chapterCount, 0);
    final session = ReadingSession(stats);
    await session.setActive(true);
    await session.openChapter(book, first);
    now = now.subtract(const Duration(hours: 1));
    await session.checkpoint();
    now = now.add(const Duration(seconds: 10));
    await session.closeChapter();
    expect(stats.total.duration, const Duration(seconds: 10));
  });

  test('旧进度不虚构统计，移除历史后统计仍跨 AppState 重启保留', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'source-a',
        'name': '统计源',
        'rules': <String, dynamic>{},
      }),
    );
    await state.saveProgress(
      book,
      chapterUrl: first.url,
      chapterTitle: first.title,
      chapterIndex: 0,
      chapterCount: 2,
    );
    expect(state.readingStats.total.chapterCount, 0);
    await state.readingStats.record(
      book,
      first,
      from: now.subtract(const Duration(minutes: 2)),
      to: now,
    );
    await state.removeReadingHistory(state.readingHistory.single.key);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.readingStats.total.duration, const Duration(minutes: 2));
    expect(restored.readingStats.total.chapterCount, 1);
    expect(restored.readingHistory, isEmpty);
    expect(restored.progressFor(book.bookUrl)?.chapterUrl, first.url);
  });

  test('损坏单日记录不影响其它日期，整份格式损坏时从空统计启动', () async {
    final prefs = await SharedPreferences.getInstance();
    final valid = {
      'milliseconds': 60000,
      'books': ['book'],
      'chapters': ['chapter'],
    };
    await prefs.setString(
      'cf.readingStats',
      jsonEncode({
        '2026-09-08': valid,
        '2026-02-31': valid,
        'broken': valid,
        '2026-09-07': {...valid, 'milliseconds': -1},
        '2026-09-06': {...valid, 'chapters': 123},
      }),
    );
    await stats.load();
    expect(stats.total.duration, const Duration(minutes: 1));
    expect(stats.total.activeDays, 1);
    for (final raw in ['{broken', '[]', 'null', 123]) {
      SharedPreferences.setMockInitialValues({'cf.readingStats': raw});
      await stats.load();
      expect(stats.total.duration, Duration.zero);
      expect(stats.total.chapterCount, 0);
    }
  });

  test('时长显示区分零、不到一分钟、分钟和小时', () {
    expect(formatReadingDuration(Duration.zero), '0 分钟');
    expect(formatReadingDuration(const Duration(seconds: 30)), '不足 1 分钟');
    expect(formatReadingDuration(const Duration(minutes: 1)), '1 分钟');
    expect(formatReadingDuration(const Duration(hours: 2)), '2 小时');
    expect(formatReadingDuration(const Duration(minutes: 90)), '1 小时 30 分钟');
  });
}
