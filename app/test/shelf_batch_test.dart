import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/comic_reading_stats_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  final serial = Book(name: '连载漫画', kind: '连载中', bookUrl: '/serial');
  final done = Book(name: '完结漫画', kind: '完结', bookUrl: '/done');
  final extra = Book(name: '另一连载', kind: '连载中', bookUrl: '/extra');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    for (final book in [serial, done, extra]) {
      await state.toggleShelf(book);
    }
  });

  tearDown(() => state.dispose());

  Future<void> showShelf(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder coverOf(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
    matching: find.byType(BookCover),
  );

  testWidgets('顶栏或长按进入多选，点按切换且不打开详情，全选作用于当前筛选', (tester) async {
    await showShelf(tester);
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量管理'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0'), findsOneWidget);
    await tester.tap(coverOf(serial.name));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.byType(BookDetailScreen), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '连载中'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2'), findsOneWidget);
    expect(find.text(done.name), findsNothing);

    await tester.tap(find.byTooltip('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0'), findsOneWidget);
    await tester.longPress(coverOf(serial.name));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    await tester.tap(coverOf(serial.name));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量替换或追加分组，确认后移出书架并保留进度', (tester) async {
    final follow = await state.shelfGroups.create('追更');
    final fav = await state.shelfGroups.create('喜爱');
    await state.assignShelfGroups(serial, [follow]);
    await state.saveProgress(
      serial,
      chapterUrl: '/c1',
      chapterTitle: '第一话',
      chapterIndex: 0,
      chapterCount: 3,
    );
    await showShelf(tester);
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置分组'));
    await tester.pumpAndSettle();
    expect(find.text('设置分组 · 已选 3 本'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('assign-$fav')));
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(state.shelfGroups.groupsFor(serial.bookUrl), {follow, fav});
    expect(state.shelfGroups.groupsFor(done.bookUrl), {fav});

    await tester.tap(find.text('设置分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('assign-$fav')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('assign-$follow')));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.shelfGroups.groupsFor(serial.bookUrl), {follow});
    expect(state.shelfGroups.groupsFor(done.bookUrl), {follow});

    await tester.tap(coverOf(done.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.shelf, hasLength(3));
    await tester.tap(find.text('移出书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移出'));
    await tester.pumpAndSettle();
    expect(state.shelf, hasLength(1));
    expect(state.inShelf(done), isTrue);
    expect(state.inShelf(serial), isFalse);
    expect(state.progressFor(serial.bookUrl)?.chapterTitle, '第一话');
    expect(find.textContaining('已选'), findsNothing);
    expect(find.text(done.name), findsOneWidget);
    expect(find.text(extra.name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索结果上批量清除角标，单本可打开统计', (tester) async {
    await state.saveDetailCache(serial, [
      Chapter(title: '第1话', url: '/c1'),
      Chapter(title: '第2话', url: '/c2'),
    ]);
    await state.saveDetailCache(done, [Chapter(title: '终章', url: '/end')]);
    await showShelf(tester);
    await tester.enterText(find.byType(TextField), '连载');
    await tester.pumpAndSettle();
    await tester.longPress(coverOf(serial.name));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(coverOf(extra.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除更新角标'));
    await tester.pumpAndSettle();
    expect(state.shelfUpdateFor(serial), isNull);
    expect(state.shelfUpdateFor(done)?.unreadCount, 1);

    await tester.tap(coverOf(extra.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读统计'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicReadingStatsScreen), findsOneWidget);
    expect(find.text('单本阅读统计'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
