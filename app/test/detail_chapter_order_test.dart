import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

List<Chapter> _chapters(int count) => List.generate(
  count,
  (i) => Chapter(
    title: '第${i + 1}话',
    url: 'https://order.example/chapter/${i + 1}',
  ),
);

void main() {
  late AppState state;
  late SourceService service;
  late Book book;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    final source = ComicSource.fromJson({
      'id': 'chapter-order',
      'name': '漫画源',
      'url': 'https://order.example',
    });
    await state.addSourceManual(source);
    book = Book(name: '漫画', bookUrl: '${source.url}/book', sourceId: source.id);
    service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher((_) => '<html></html>'),
    );
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  testWidgets('千话目录可倒序查看最新话，阅读和续读始终使用原章节顺序', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chapters = _chapters(1300);
    await state.saveProgress(
      book,
      chapterUrl: chapters.last.url,
      chapterTitle: chapters.last.title,
      chapterIndex: 1299,
      chapterCount: chapters.length,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async => (book, chapters),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstTitleLeft = tester.getTopLeft(find.text('第1话')).dx;
    await tester.ensureVisible(find.widgetWithText(TextButton, '正序'));
    await tester.tap(find.widgetWithText(TextButton, '正序'));
    await tester.pumpAndSettle();
    expect(find.text('第1300话').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.text('第1300话')).dx, firstTitleLeft);
    expect(
      tester
          .widget<ChapterTile>(find.widgetWithText(ChapterTile, '第1300话'))
          .isCurrent,
      isTrue,
    );
    final currentTapArea = tester.getRect(
      find.descendant(
        of: find.widgetWithText(ChapterTile, '第1300话'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.tapAt(
      Offset(currentTapArea.center.dx, currentTapArea.bottom - 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第1300话'), findsOneWidget);
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第1300话'), findsOneWidget);
    await tester.tap(find.text('上一话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第1299话'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '倒序'), findsOneWidget);
    expect(
      tester
          .widget<ChapterTile>(find.widgetWithText(ChapterTile, '第1299话'))
          .isCurrent,
      isTrue,
    );
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1298);
    await tester.tap(find.widgetWithText(TextButton, '倒序'));
    await tester.pumpAndSettle();
    expect(find.text('第1话').hitTestable(), findsOneWidget);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1298);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字号离线目录可排序，后台新增章节后保持倒序：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await state.saveDetailCache(book, _chapters(3));
      final fresh = Completer<(Book, List<Chapter>)>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BookDetailScreen(
            book: book,
            appState: state,
            detailLoaderOverride: (_) => fresh.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(TextButton, '正序'));
      await tester.tap(find.widgetWithText(TextButton, '正序'));
      await tester.pumpAndSettle();
      expect(find.text('离线目录'), findsOneWidget);
      expect(
        tester.widget<ChapterTile>(find.byType(ChapterTile).first).title,
        '第3话',
      );
      fresh.complete((book, _chapters(4)));
      await tester.pumpAndSettle();
      expect(find.text('离线目录'), findsNothing);
      expect(find.widgetWithText(TextButton, '倒序'), findsOneWidget);
      expect(
        tester.widget<ChapterTile>(find.byType(ChapterTile).first).title,
        '第4话',
      );
      expect(state.detailCacheFor(book.bookUrl)!.chapters.first.title, '第1话');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
