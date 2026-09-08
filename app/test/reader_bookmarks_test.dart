import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/chapter_bookmark_sheet.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

Future<void> _dismissSnackBar(WidgetTester tester) async {
  await tester.pump();
  ScaffoldMessenger.of(
    tester.element(find.byType(ReaderScreen)),
  ).hideCurrentSnackBar();
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;
  late Book book;
  late List<Chapter> chapters;

  Future<void> openReader(WidgetTester tester) async {
    final urls = [
      for (final chapter in chapters) '${chapter.url}/page-1.png',
    ];
    await cacheReaderTestImages(tester, urls);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: ComicSource.fromJson({
              'id': 'bookmark-reader',
              'url': 'https://bookmark.example',
              'rules': {'contentUrl': '.page@src'},
            }),
            fetcher: FakeFetcher((uri) {
              final page = '${uri.origin}${uri.path}/page-1.png';
              return '<img class="page" src="$page">';
            }),
          ),
          book: book,
          chapters: chapters,
          initialIndex: 0,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    book = Book(
      name: '书签漫画',
      bookUrl: 'https://bookmark.example/book',
      sourceId: 'bookmark-reader',
    );
    chapters = List.generate(
      3,
      (i) => Chapter(
        title: '第${i + 1}话',
        url: 'https://bookmark.example/c${i + 1}',
      ),
    );
  });
  tearDown(() => state.dispose());

  testWidgets('阅读器顶栏可添加和移除当前话书签，设置菜单可跳到已收藏章节', (tester) async {
    await openReader(tester);
    expect(find.byTooltip('添加书签'), findsOneWidget);
    await tester.tap(find.byTooltip('添加书签'));
    await _dismissSnackBar(tester);
    expect(find.byTooltip('移除书签'), findsOneWidget);
    expect(state.isChapterBookmarked(book, chapters.first), isTrue);

    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('书签漫画 · 第2话'), findsOneWidget);
    await tester.tap(find.byTooltip('添加书签'));
    await _dismissSnackBar(tester);
    expect(state.bookmarksFor(book).map((e) => e.chapter.title), [
      '第2话',
      '第1话',
    ]);

    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    expect(find.text('本书书签'), findsOneWidget);
    expect(find.text('2 话'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-chapter-bookmarks')));
    await tester.pumpAndSettle();
    expect(find.byType(ChapterBookmarkSheet), findsOneWidget);
    await tester.tap(find.text('第1话'));
    await tester.pumpAndSettle();
    expect(find.text('书签漫画 · 第1话'), findsOneWidget);
    expect(find.byTooltip('移除书签'), findsOneWidget);

    await tester.tap(find.byTooltip('移除书签'));
    await _dismissSnackBar(tester);
    expect(find.byTooltip('添加书签'), findsOneWidget);
    expect(state.isChapterBookmarked(book, chapters.first), isFalse);
    expect(state.bookmarksFor(book).single.chapter.title, '第2话');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('阅读设置可收藏本章，书签列表可移除且不改变当前话', (tester) async {
    await openReader(tester);
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加本章书签'));
    await tester.tap(find.text('添加本章书签'));
    await tester.pump();
    expect(find.text('已添加书签'), findsOneWidget);
    expect(find.text('移除本章书签'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(ReaderScreen)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-chapter-bookmarks')));
    await tester.pumpAndSettle();
    expect(find.text('第1话'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ChapterBookmarkSheet),
        matching: find.byTooltip('移除书签'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
    expect(state.bookmarksFor(book), isEmpty);
    expect(find.text('书签漫画 · 第1话'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
