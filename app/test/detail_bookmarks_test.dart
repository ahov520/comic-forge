import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/chapter_bookmark_sheet.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  late AppState state;
  final book = Book(name: '同名漫画', sourceId: 'bookmarks', bookUrl: '/book');
  final otherSource = Book.fromJson({...book.toJson(), 'sourceId': 'other'});
  final chapters = [
    Chapter(title: '第一话', url: '/c1'),
    Chapter(title: '第二话', url: '/c2'),
    Chapter(title: '第三话', url: '/c3'),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'bookmarks',
        'name': '书签源',
        'url': 'https://bookmark.example',
        'rules': {'contentUrl': '.page@src'},
      }),
    );
    final service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher((_) => '<html></html>'),
    );
  });

  tearDown(() {
    state.dispose();
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
  });

  Future<void> showDetail(
    WidgetTester tester, {
    Book? shown,
    List<Chapter>? shownChapters,
    double textScale = 1,
  }) async {
    final target = shown ?? book;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BookDetailScreen(
          book: target,
          appState: state,
          detailLoaderOverride: (_) async =>
              (target, shownChapters ?? chapters),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('详情页列出该书书签并跳到对应章节，同名漫画互不混入', (tester) async {
    await state.toggleChapterBookmark(
      otherSource,
      chapter: chapters[2],
      chapterIndex: 2,
    );
    await state.toggleChapterBookmark(
      book,
      chapter: chapters[1],
      chapterIndex: 1,
    );
    await showDetail(tester);

    expect(find.text('书签'), findsOneWidget);
    expect(find.text('1 话'), findsOneWidget);
    final marked = tester.widget<ChapterTile>(
      find.widgetWithText(ChapterTile, '第二话'),
    );
    expect(marked.isBookmarked, isTrue);
    expect(
      tester.widget<ChapterTile>(find.widgetWithText(ChapterTile, '第一话'))
          .isBookmarked,
      isFalse,
    );

    await tester.ensureVisible(find.byKey(const Key('detail-chapter-bookmarks')));
    await tester.tap(find.byKey(const Key('detail-chapter-bookmarks')));
    await tester.pumpAndSettle();
    expect(find.byType(ChapterBookmarkSheet), findsOneWidget);
    expect(find.text('第二话'), findsWidgets);
    expect(find.text('第三话'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(ChapterBookmarkSheet),
      matching: find.text('第二话'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('同名漫画 · 第二话'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空目录仍显示书签入口，无记录时为空态', (tester) async {
    await showDetail(tester, shownChapters: const []);
    expect(find.text('暂无章节'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('detail-chapter-bookmarks')));
    await tester.tap(find.byKey(const Key('detail-chapter-bookmarks')));
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
    expect(find.textContaining('阅读时点顶栏书签'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('源停用时离线详情仍可打开书签列表', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.toggleChapterBookmark(
      book,
      chapter: chapters.first,
      chapterIndex: 0,
    );
    await state.saveDetailCache(book, chapters);
    await state.toggleSource('bookmarks');
    await showDetail(tester, textScale: 2);

    expect(find.text('启用漫画源'), findsOneWidget);
    final entry = find.byKey(
      const Key('detail-chapter-bookmarks'),
      skipOffstage: false,
    );
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ChapterBookmarkSheet), findsOneWidget);
    expect(find.text('第一话').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
