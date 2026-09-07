import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(String id) => ComicSource.fromJson({
  'id': id,
  'name': '漫画源 $id',
  'url': 'https://$id.example',
  'rules': {
    'searchUrl': '/search',
    'searchList': '.item',
    'searchName': '.title@text',
    'searchBookUrl': '.title@href',
  },
});

void main() {
  late AppState state;
  late SourceService service;
  late Book book;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source('current'));
    book = Book(
      name: '漫画',
      sourceId: 'current',
      bookUrl: 'https://current.example/book',
    );
    service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher(
        (_) => '<div class="item"><a class="title" href="/book">漫画</a></div>',
      ),
    );
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<void> showDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async => (
            book,
            List.generate(
              40,
              (i) => Chapter(
                title: '第${i + 1}话',
                url: 'https://current.example/chapter/${i + 1}',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('详情横屏旋转后避开侧边刘海，末话可在底部手势区上方点开', (tester) async {
    tester.view.physicalSize = const Size(720, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await showDetail(tester);

    for (final insets in [
      const FakeViewPadding(left: 60, bottom: 34),
      const FakeViewPadding(right: 60, bottom: 34),
    ]) {
      tester.view.padding = insets;
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      final cover = tester.getRect(find.byType(BookCover));
      expect(cover.left, greaterThanOrEqualTo(insets.left));
      await tester.scrollUntilVisible(
        find.text('第40话'),
        250,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final lastChapter = find.widgetWithText(ChapterTile, '第40话');
      final tapArea = find.descendant(
        of: lastChapter,
        matching: find.byType(InkWell),
      );
      final rect = tester.getRect(tapArea);
      expect(rect.left, greaterThanOrEqualTo(insets.left));
      expect(rect.right, lessThanOrEqualTo(720 - insets.right));
      expect(rect.bottom, lessThanOrEqualTo(340 - insets.bottom));
      await tester.tap(tapArea);
      await tester.pumpAndSettle();
      expect(find.text('漫画 · 第40话'), findsOneWidget);
      expect(state.progressFor(book.bookUrl)?.chapterIndex, 39);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('换源面板最后一项避开系统手势区并能完成切换', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 36, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    for (var i = 1; i <= 8; i++) {
      await state.addSourceManual(_source('alternative-$i'));
    }
    await showDetail(tester);
    await tester.tap(find.byTooltip('换源（8 源命中）'));
    await tester.pumpAndSettle();
    final last = find.byWidgetPredicate(
      (widget) => widget is BookTile && widget.book.sourceId == 'alternative-8',
    );
    await tester.scrollUntilVisible(
      last,
      250,
      scrollable: find.descendant(
        of: find.byType(SwitchSourcePanel),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    final tapArea = find.descendant(of: last, matching: find.byType(InkWell));
    expect(tester.getRect(tapArea).bottom, lessThanOrEqualTo(720 - 34));
    await tester.tap(tapArea);
    await tester.pumpAndSettle();
    expect(find.byType(SwitchSourcePanel), findsNothing);
    expect(
      tester
          .widget<BookDetailScreen>(find.byType(BookDetailScreen))
          .book
          .sourceId,
      'alternative-8',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
