import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_stats.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

class _ImagesRuntime extends SourceRuntime {
  _ImagesRuntime(ComicSource source, this.loadImages)
    : super(source: source, fetcher: FakeFetcher((_) => ''));

  final Future<List<String>> Function(String) loadImages;

  @override
  Future<List<String>> images(String chapterUrl, {int maxPages = 10}) =>
      loadImages(chapterUrl);
}

void main() {
  late AppState state;
  late DateTime now;
  late ComicSource source;
  late Book book;
  late List<Chapter> chapters;
  late Future<List<String>> Function(String) loadImages;
  final imageUrls = List.generate(
    3,
    (i) => 'https://stats.example/image$i.png',
  );
  final requests = <String>[];
  final service = SourceService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 8, 12);
    state = AppState(readingStats: ReadingStats(now: () => now));
    source = ComicSource.fromJson({
      'id': 'reader-stats',
      'name': '统计源',
      'url': 'https://stats.example',
      'rules': <String, dynamic>{},
    });
    await state.addSourceManual(source);
    book = Book(
      name: '统计漫画',
      sourceId: source.id,
      bookUrl: 'https://stats.example/book',
    );
    chapters = List.generate(
      3,
      (i) => Chapter(title: '第${i + 1}话', url: 'https://stats.example/c$i'),
    );
    loadImages = (url) async => [
      imageUrls[chapters.indexWhere((chapter) => chapter.url == url)],
    ];
    requests.clear();
    service.debugClearSwitchCache();
  });

  tearDown(() {
    state.dispose();
    service.debugClearSwitchCache();
  });

  Future<void> showReader(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await cacheReaderTestImages(tester, imageUrls);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: _ImagesRuntime(source, (url) {
            requests.add(url);
            return loadImages(url);
          }),
          book: book,
          chapters: chapters,
          initialIndex: 0,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('加载等待和预加载不计入统计，退后台暂停，退出后时长持久化', (tester) async {
    final loading = Completer<List<String>>();
    loadImages = (url) => url == chapters.first.url
        ? loading.future
        : Future.value([imageUrls[1]]);
    await showReader(tester);
    expect(requests, contains(chapters[1].url), reason: '下一话已预加载');
    now = now.add(const Duration(minutes: 5));
    expect(state.readingStats.total.chapterCount, 0);
    loading.complete([imageUrls.first]);
    await tester.pumpAndSettle();
    expect(state.readingStats.total.chapterCount, 1);
    now = now.add(const Duration(seconds: 30));
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pump(const Duration(seconds: 1));
    expect(state.readingStats.total.duration, const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(state.readingStats.total.duration, const Duration(seconds: 30));
    now = now.add(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 20));
    await closeReader(tester);
    expect(state.readingStats.total.duration, const Duration(seconds: 50));
    final restored = ReadingStats();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.total.duration, const Duration(seconds: 50));
    expect(restored.total.bookCount, 1);
    expect(restored.total.chapterCount, 1);
  });

  for (final mode in ['scroll', 'paged']) {
    testWidgets('目录遮挡暂停计时，切话和重读准确去重：$mode', (tester) async {
      await state.setReaderMode(mode);
      await showReader(tester);
      now = now.add(const Duration(seconds: 40));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(state.readingStats.total.duration, const Duration(seconds: 40));
      now = now.add(const Duration(minutes: 10));
      await tester.tap(find.text('第2话'));
      await tester.pumpAndSettle();
      expect(state.readingStats.total.duration, const Duration(seconds: 40));
      expect(state.readingStats.total.chapterCount, 2);
      now = now.add(const Duration(seconds: 30));
      await tester.tap(find.text('上一话'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 15));
      await closeReader(tester);
      expect(state.readingStats.total.duration, const Duration(seconds: 85));
      expect(state.readingStats.total.chapterCount, 2);
      expect(state.readingStats.total.bookCount, 1);
    });
  }

  testWidgets('后台收到图片列表时等待恢复前台后才开始统计', (tester) async {
    final loading = Completer<List<String>>();
    loadImages = (_) => loading.future;
    await showReader(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 1));
    loading.complete([imageUrls.first]);
    await tester.pump();
    expect(state.readingStats.total.chapterCount, 0);
    now = now.add(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.readingStats.total.chapterCount, 1);
    now = now.add(const Duration(seconds: 20));
    await closeReader(tester);
    expect(state.readingStats.total.duration, const Duration(seconds: 20));
  });

  testWidgets('空章、失败和晚到的旧请求不计入，成功重试后才记录当前章节', (tester) async {
    final old = Completer<List<String>>();
    loadImages = (url) async {
      if (url == chapters[0].url) return old.future;
      if (url == chapters[1].url) return [];
      throw StateError('offline');
    };
    await showReader(tester);
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    old.complete([imageUrls.first]);
    await tester.pumpAndSettle();
    expect(find.text('本话暂无图片'), findsOneWidget);
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载章节'), findsOneWidget);
    now = now.add(const Duration(minutes: 5));
    expect(state.readingStats.total.chapterCount, 0);
    loadImages = (_) async => [imageUrls[2]];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 15));
    await closeReader(tester);
    expect(state.readingStats.total.chapterCount, 1);
    expect(state.readingStats.total.duration, const Duration(seconds: 15));
    expect(tester.takeException(), isNull);
  });
}
