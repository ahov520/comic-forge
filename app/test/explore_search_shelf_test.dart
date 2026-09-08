import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source({
  String name = '测试源',
  String url = 'https://example.com',
  String entries = '连载::/serial',
}) => ComicSource.fromPpcatFlat({
  'bookSourceName': name,
  'bookSourceUrl': url,
  'exploreUrl': entries,
  'ruleSearchUrl': '/search?q=searchKey',
  'ruleSearchList': 'class.item',
  'ruleSearchName': 'class.title@text',
  'ruleSearchBookUrl': 'class.title@href',
});

String _books(String name, {String path = '/book/1'}) =>
    '<div class="item"><a class="title" href="$path">$name</a></div>';

Finder _category(String name) => find.widgetWithText(ChoiceChip, name);

void main() {
  late AppState state;
  late FakeFetcher fetcher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source());
    fetcher = FakeFetcher((uri) {
      if (uri.path == '/serial') return _books('探索漫画');
      return _books('搜索漫画');
    });
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  Future<AppState> restart() async {
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    return restored;
  }

  Future<void> _addGroupedBook() async {
    final grouped = Book(
      name: '已分组',
      bookUrl: 'https://example.com/grouped',
      sourceId: state.sources.single.id,
    );
    await state.toggleShelf(grouped);
    final id = await state.shelfGroups.create('追更');
    await state.assignShelfGroups(grouped, [id]);
  }

  testWidgets(
    '探索结果可一键加入并持久化，已在书架可移出且不打乱其它分组',
    (tester) async {
      await _addGroupedBook();
      await tester.pumpWidget(MaterialApp(home: ExploreScreen(state: state)));
      await tester.tap(_category('连载'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(BookTile, '探索漫画'), findsOneWidget);
      expect(find.text('加入'), findsOneWidget);

      await tester.tap(find.byTooltip('加入书架'));
      await tester.pumpAndSettle();
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );
      expect(find.byTooltip('已在书架'), findsOneWidget);
      expect(find.text('已在'), findsOneWidget);
      expect(find.byType(BookDetailScreen), findsNothing);

      final groupedUrl = 'https://example.com/grouped';
      final groupId = state.shelfGroups.groups.single.id;
      expect(state.shelfGroups.groupsFor(groupedUrl), {groupId});

      final restored = await restart();
      expect(
        restored.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );
      expect(restored.shelfGroups.groupsFor(groupedUrl), {groupId});

      await tester.tap(find.byTooltip('已在书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出书架'));
      await tester.pumpAndSettle();
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isFalse,
      );
      expect(find.byTooltip('加入书架'), findsOneWidget);
      expect(state.shelfGroups.groupsFor(groupedUrl), {groupId});
      expect(find.byType(BookDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '探索已在书架时可打开该书详情，点卡片仍进详情且不移出',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: ExploreScreen(state: state)));
      await tester.tap(_category('连载'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加入书架'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('已在书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<BookDetailScreen>(find.byType(BookDetailScreen))
            .book
            .bookUrl,
        'https://example.com/book/1',
      );
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('探索漫画'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '搜索结果可一键加入并持久化，已在书架可移出且不打乱其它分组',
    (tester) async {
      await _addGroupedBook();
      await tester.pumpWidget(MaterialApp(home: SearchScreen(state: state)));
      await tester.enterText(find.byType(TextField), '海贼王');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(BookTile, '搜索漫画'), findsOneWidget);
      expect(find.text('加入'), findsOneWidget);

      await tester.tap(find.byTooltip('加入书架'));
      await tester.pumpAndSettle();
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );
      expect(find.byTooltip('已在书架'), findsOneWidget);
      expect(find.byType(BookDetailScreen), findsNothing);

      final groupedUrl = 'https://example.com/grouped';
      final groupId = state.shelfGroups.groups.single.id;
      expect(state.shelfGroups.groupsFor(groupedUrl), {groupId});

      final restored = await restart();
      expect(
        restored.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isTrue,
      );
      expect(restored.shelfGroups.groupsFor(groupedUrl), {groupId});

      await tester.tap(find.byTooltip('已在书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出书架'));
      await tester.pumpAndSettle();
      expect(
        state.inShelf(Book(bookUrl: 'https://example.com/book/1')),
        isFalse,
      );
      expect(find.byTooltip('加入书架'), findsOneWidget);
      expect(state.shelfGroups.groupsFor(groupedUrl), {groupId});
      expect(find.byType(BookDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
