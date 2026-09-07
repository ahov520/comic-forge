import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  late AppState state;
  late ComicSource source;
  late Book book;
  late List<Chapter> chapters;
  late int loads;
  late Future<(Book, List<Chapter>)> Function() loadDetail;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'cached-source',
      'name': '社区源',
      'url': 'https://example.com',
    });
    await state.addSourceManual(source);
    book = Book(
      name: '离线漫画',
      sourceId: source.id,
      bookUrl: '${source.url}/book',
    );
    chapters = [
      Chapter(title: '第一话', url: '${source.url}/chapter/1'),
      Chapter(title: '第二话', url: '${source.url}/chapter/2'),
    ];
    await state.saveDetailCache(book, chapters);
    await state.saveProgress(
      book,
      chapterUrl: chapters.last.url,
      chapterTitle: chapters.last.title,
      chapterIndex: 1,
      chapterCount: chapters.length,
    );
    loads = 0;
    loadDetail = () async => (book, chapters);
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher((_) => '<html></html>'),
    );
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  Future<void> showDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async {
            loads++;
            return loadDetail();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectUnavailable() {
    expect(find.text('续读 2'), findsNothing);
    expect(find.text('第一话'), findsOneWidget);
    expect(find.text('第二话'), findsOneWidget);
    expect(find.byType(DetailSkeleton), findsNothing);
    expect(
      find
          .byType(ChapterTile)
          .evaluate()
          .map((element) => (element.widget as ChapterTile).onTap),
      everyElement(isNull),
    );
  }

  testWidgets('缓存目录的来源已停用，主按钮明确启用来源并恢复续读', (tester) async {
    await state.toggleSource(source.id);
    await showDetail(tester);
    expectUnavailable();
    expect(find.text('启用漫画源'), findsOneWidget);
    expect(find.text('漫画源已停用，启用后即可继续阅读。'), findsOneWidget);
    expect(loads, 0);

    await tester.tap(find.text('启用漫画源'));
    await tester.pumpAndSettle();
    expect(source.enabled, isTrue);
    expect(loads, 1);
    expect(find.text('续读 2'), findsOneWidget);
    await tester.tap(find.text('续读 2'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('离线漫画 · 第二话'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final restore in [false, true]) {
    testWidgets('缓存来源已删除，管理源返回${restore ? '恢复阅读' : '仍保留恢复入口'}', (tester) async {
      await state.removeSource(source.id);
      await showDetail(tester);
      expectUnavailable();
      expect(find.text('管理源'), findsOneWidget);
      expect(loads, 0);
      await tester.tap(find.text('管理源'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceScreen), findsOneWidget);
      if (restore) await state.addSourceManual(source);
      Navigator.of(tester.element(find.byType(SourceScreen))).pop();
      await tester.pumpAndSettle();
      if (restore) {
        expect(find.text('续读 2'), findsOneWidget);
        expect(loads, 1);
        final chapter = tester.widget<ChapterTile>(
          find.widgetWithText(ChapterTile, '第二话'),
        );
        expect(chapter.onTap, isNotNull);
      } else {
        expectUnavailable();
        expect(find.text('管理源'), findsOneWidget);
        expect(loads, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final remove in [false, true]) {
    testWidgets('详情已显示后${remove ? '删除' : '停用'}来源，阅读入口即时改为恢复操作', (tester) async {
      await showDetail(tester);
      expect(find.text('续读 2'), findsOneWidget);
      if (remove) {
        await state.removeSource(source.id);
      } else {
        await state.toggleSource(source.id);
      }
      await tester.pumpAndSettle();
      expectUnavailable();
      expect(find.text(remove ? '管理源' : '启用漫画源'), findsOneWidget);
      expect(loads, 1, reason: '来源不可用时不继续请求详情');
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('恢复来源后旧刷新${fails ? '失败' : '成功'}晚到，不回滚新目录或缓存', (tester) async {
      final oldResponse = Completer<(Book, List<Chapter>)>();
      final freshResponse = Completer<(Book, List<Chapter>)>();
      loadDetail = () => loads == 1 ? oldResponse.future : freshResponse.future;
      await showDetail(tester);
      expect(loads, 1);
      await state.toggleSource(source.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用漫画源'));
      await tester.pumpAndSettle();
      expect(loads, 2);

      final fresh = [
        Chapter(title: '新目录第一话', url: '${source.url}/chapter/new'),
      ];
      freshResponse.complete((book, fresh));
      await tester.pumpAndSettle();
      expect(find.text('新目录第一话'), findsOneWidget);
      if (fails) {
        oldResponse.completeError(FetchException('old offline response'));
      } else {
        oldResponse.complete((book, chapters));
      }
      await tester.pumpAndSettle();
      await state.toggleShelf(book);
      await tester.pumpAndSettle();
      expect(find.text('新目录第一话'), findsOneWidget);
      expect(find.text('第一话'), findsNothing);
      expect(
        state.detailCacheFor(book.bookUrl)!.chapters.single.title,
        '新目录第一话',
      );
      final restored = AppState();
      addTearDown(restored.dispose);
      await restored.load();
      expect(
        restored.detailCacheFor(book.bookUrl)!.chapters.single.title,
        '新目录第一话',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
