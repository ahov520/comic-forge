import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_history.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late ComicSource source;

  Book book(String name, {String? url, String? sourceId}) => Book(
    name: name,
    bookUrl: url ?? 'https://history.example/$name',
    sourceId: sourceId ?? source.id,
  );

  Future<void> read(Book book, int index) => state.saveProgress(
    book,
    chapterUrl: '${book.bookUrl}/$index',
    chapterTitle: '第${index + 1}话',
    chapterIndex: index,
    chapterCount: 10,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'history-source',
      'name': '历史源',
      'url': 'https://history.example',
      'rules': <String, dynamic>{},
    });
    await state.addSourceManual(source);
  });
  tearDown(() => state.dispose());

  test('未收藏漫画也记录完整快照，重复阅读更新章节并移到最前', () async {
    final a = book('甲漫画')..coverUrl = 'https://history.example/cover.png';
    final b = book('乙漫画');
    await read(a, 0);
    await read(b, 2);
    await read(a, 4);
    expect(state.shelf, isEmpty);
    expect(state.readingHistory.map((e) => e.book.name), ['甲漫画', '乙漫画']);
    expect(state.readingHistory.first.chapter.title, '第5话');
    expect(state.readingHistory.first.chapterIndex, 4);
    a.name = '被外部修改的对象';
    expect(state.readingHistory.first.book.name, '甲漫画');
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.readingHistory.first.book.name, '甲漫画');
    expect(restored.readingHistory.first.book.coverUrl, a.coverUrl);
    expect(restored.readingHistory.first.chapter.url, '${a.bookUrl}/4');
  });

  test('按源和书籍链接去重，同一链接的不同源保留各自章节快照', () async {
    final a = book('甲源漫画', url: '/same', sourceId: 'a');
    final b = book('乙源漫画', url: '/same', sourceId: 'b');
    await read(a, 2);
    await read(b, 6);
    expect(state.readingHistory.length, 2);
    expect(state.readingHistory.first.chapterIndex, 6);
    expect(state.readingHistory.last.chapterIndex, 2);
    expect(
      state.readingHistory.first.key,
      isNot(state.readingHistory.last.key),
    );
  });

  test('移除记录跨重启生效，书架和章节、翻页、滚动进度不受影响', () async {
    final a = book('保留续读');
    await state.toggleShelf(a);
    await read(a, 3);
    final progress = state.progressFor(a.bookUrl)!;
    await state.saveReaderPage(progress.chapterUrl, 7);
    await state.saveScrollOffset(progress.chapterUrl, 1234);
    await state.removeReadingHistory(state.readingHistory.single.key);
    expect(state.readingHistory, isEmpty);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.readingHistory, isEmpty);
    expect(restored.inShelf(a), isTrue);
    expect(restored.progressFor(a.bookUrl)?.toJson(), progress.toJson());
    expect(restored.readerPageFor(progress.chapterUrl), 7);
    expect(restored.scrollOffsetFor(progress.chapterUrl), 1234);
    await read(a, 4);
    expect(state.readingHistory.single.chapterIndex, 4);
  });

  test('并发保存与移除不会被晚到的持久化写入恢复旧历史', () async {
    final a = book('甲');
    final b = book('乙');
    final saving = read(a, 1);
    final removing = state.removeReadingHistory(
      state.readingHistory.single.key,
    );
    final latest = read(b, 2);
    await Future.wait([saving, removing, latest]);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.readingHistory.map((e) => e.book.name), ['乙']);
    expect(restored.progressFor(a.bookUrl), isNotNull);
  });

  test('升级时从书架与详情缓存补全旧进度，缺少书名也保留记录', () async {
    final a = book('书架漫画');
    final b = book('缓存漫画');
    final unknown = book('已遗失名称');
    final readings = [a, b, unknown].indexed
        .map(
          (pair) => ReadingProgress(
            bookUrl: pair.$2.bookUrl,
            sourceId: source.id,
            chapterUrl: '${pair.$2.bookUrl}/read',
            chapterTitle: '第三话',
            chapterIndex: 2,
            chapterCount: 5,
            at: 100 + pair.$1,
          ),
        )
        .toList();
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([source.toJson()]),
      'cf.shelf': jsonEncode([a.toJson()]),
      'cf.progress': jsonEncode({
        for (final p in readings) p.bookUrl: p.toJson(),
      }),
      'cf.detailCache': jsonEncode({
        b.bookUrl: CachedDetail(
          book: b,
          chapters: [Chapter(title: '第三话', url: '${b.bookUrl}/read')],
          at: 100,
        ).toJson(),
      }),
    });
    await state.load();
    expect(state.readingHistory.map((e) => e.book.name), [
      '未命名漫画',
      '缓存漫画',
      '书架漫画',
    ]);
    expect(state.readingHistory.first.book.bookUrl, unknown.bookUrl);
    final key = state.readingHistory.first.key;
    await state.removeReadingHistory(key);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.readingHistory.any((e) => e.key == key), isFalse);
    expect(restored.progress.length, 3);
  });

  test('恢复历史时跳过损坏记录，重复项保留最新并按时间排序', () async {
    final a = book('甲');
    Map<String, dynamic> entry(Book b, int at) => ReadingHistoryEntry(
      book: b,
      chapter: Chapter(url: '${b.bookUrl}/c1'),
      chapterIndex: 0,
      chapterCount: 1,
      at: at,
    ).toJson();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cf.readingHistory',
      jsonEncode([
        entry(a, 10),
        'bad',
        {'book': 12},
        entry(book('乙'), 20),
        entry(a, 30),
      ]),
    );
    await state.load();
    expect(state.readingHistory.map((e) => e.book.name), ['甲', '乙']);
    expect(state.readingHistory.first.at, 30);
  });

  for (final saved in ['[]', '{broken', 'true', 123]) {
    test('空历史或损坏格式不触发旧进度重新迁移：$saved', () async {
      final a = book('已移除漫画');
      await read(a, 1);
      final prefs = await SharedPreferences.getInstance();
      if (saved is String) {
        await prefs.setString('cf.readingHistory', saved);
      } else {
        await prefs.setInt('cf.readingHistory', saved as int);
      }
      await state.load();
      expect(state.readingHistory, isEmpty);
      expect(state.progressFor(a.bookUrl), isNotNull);
    });
  }

  test('较新的备份进度补入时间线且保留原时间，不把旧记录置顶', () async {
    final a = book('现有漫画');
    await read(a, 1);
    final at = state.readingHistory.single.at - 1000;
    final restoredBook = book('恢复漫画');
    await state.mergeBackup(
      sources: [],
      shelf: [restoredBook],
      repos: [],
      progress: {
        restoredBook.bookUrl: ReadingProgress(
          bookUrl: restoredBook.bookUrl,
          sourceId: source.id,
          chapterUrl: '${restoredBook.bookUrl}/c1',
          chapterTitle: '第一话',
          chapterIndex: 0,
          chapterCount: 4,
          at: at,
        ),
      },
    );
    expect(state.readingHistory.map((e) => e.book.name), ['现有漫画', '恢复漫画']);
    expect(state.readingHistory.last.at, at);
  });

  test('日期分组跨年仍区分今天和昨天，时间补齐为两位', () {
    final now = DateTime(2027, 1, 1, 0, 10);
    expect(readingHistoryDay(now.millisecondsSinceEpoch, now: now), '今天');
    expect(
      readingHistoryDay(
        DateTime(2026, 12, 31, 23, 50).millisecondsSinceEpoch,
        now: now,
      ),
      '昨天',
    );
    expect(
      readingHistoryDay(
        DateTime(2026, 12, 30).millisecondsSinceEpoch,
        now: now,
      ),
      '2026-12-30',
    );
    expect(
      readingHistoryTime(DateTime(2026, 9, 8, 9, 4).millisecondsSinceEpoch),
      '09:04',
    );
  });
}
