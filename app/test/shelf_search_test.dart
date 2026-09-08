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
  final moon = Book(
    name: 'Moon 漫画',
    author: '青山',
    kind: '连载中',
    bookUrl: '/moon',
  );
  final mountain = Book(
    name: '山海卷',
    author: 'Alice',
    kind: '已完结',
    bookUrl: '/mountain',
  );
  final extra = Book(
    name: 'Moon 番外',
    author: 'Alice',
    kind: '已完结',
    bookUrl: '/extra',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    for (final book in [moon, mountain, extra]) {
      await state.toggleShelf(book);
    }
  });

  tearDown(() => state.dispose());

  Future<void> showShelf(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('按漫画名或作者即时搜索，忽略大小写与首尾空白，空查询恢复全部藏书', (tester) async {
    await showShelf(tester);
    await search(tester, '  mOoN  ');
    expect(find.text(moon.name), findsOneWidget);
    expect(find.text(extra.name), findsOneWidget);
    expect(find.text(mountain.name), findsNothing);

    await search(tester, 'ALICE');
    expect(find.text(moon.name), findsNothing);
    expect(find.text(extra.name), findsOneWidget);
    expect(find.text(mountain.name), findsOneWidget);

    await search(tester, '青山');
    expect(find.text(moon.name), findsOneWidget);
    expect(find.byType(BookCover), findsOneWidget);

    await search(tester, '   ');
    expect(find.byType(BookCover), findsNWidgets(3));
    await search(tester, '不存在');
    expect(find.text('没有匹配的漫画'), findsOneWidget);
    expect(find.byType(BookCover), findsNothing);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.byType(BookCover), findsNWidgets(3));
    expect(state.shelf, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索与分组、连载状态共同筛选，空结果引导清空搜索时保留分类', (tester) async {
    final group = await state.shelfGroups.create('追更');
    await state.shelfGroups.assign(moon.bookUrl, [group]);
    await state.shelfGroups.assign(extra.bookUrl, [group]);
    await showShelf(tester);
    await search(tester, 'moon');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追更').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pumpAndSettle();
    expect(find.text(extra.name), findsOneWidget);
    expect(find.text(moon.name), findsNothing);
    expect(find.text(mountain.name), findsNothing);

    await search(tester, 'alice');
    expect(find.byType(BookCover), findsOneWidget);
    expect(find.text(extra.name), findsOneWidget);
    await search(tester, '不存在');
    final clear = find.widgetWithText(FilledButton, '清空搜索');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(state.shelfGroups.filter, group);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已完结'))
          .selected,
      isTrue,
    );
    expect(find.text(extra.name), findsOneWidget);
    expect(find.byType(BookCover), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索结果可打开详情和统计，返回后保留查询，收藏变化即时更新结果', (tester) async {
    await state.saveDetailCache(moon, []);
    final now = DateTime(2026, 9, 8, 12);
    await state.readingStats.record(
      moon,
      Chapter(title: '第一话', url: '/c1'),
      from: now.subtract(const Duration(minutes: 2)),
      to: now,
    );
    await showShelf(tester);
    await search(tester, 'mOoN 漫画');
    await tester.tap(find.byType(BookCover));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'mOoN 漫画',
    );
    expect(find.byType(BookCover), findsOneWidget);

    await tester.longPress(find.byType(BookCover));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读统计'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicReadingStatsScreen), findsOneWidget);
    expect(find.text('2 分钟'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'mOoN 漫画',
    );
    expect(find.byType(BookCover), findsOneWidget);

    final added = Book(name: '新作', author: 'Moon 漫画', bookUrl: '/new');
    await state.toggleShelf(added);
    await tester.pumpAndSettle();
    expect(find.byType(BookCover), findsNWidgets(2));
    await state.toggleShelf(moon);
    await tester.pumpAndSettle();
    expect(find.byType(BookCover), findsOneWidget);
    expect(find.text(added.name), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('长书架滚动后可返回搜索，匹配结果从顶部显示', (tester) async {
    for (var i = 0; i < 30; i++) {
      await state.toggleShelf(Book(name: '合辑 $i', bookUrl: '/collection-$i'));
    }
    await showShelf(tester);
    await tester.scrollUntilVisible(
      find.text('合辑 29'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('合辑 0').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await search(tester, '合辑 0');
    expect(
      find
          .descendant(of: find.byType(SliverGrid), matching: find.text('合辑 0'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(BookCover), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字号和键盘占位下可搜索及清空，不产生布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await showShelf(tester, textScale: 2);
    await search(tester, '不存在');
    await tester.ensureVisible(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await search(tester, '青山');
    tester.view.resetViewInsets();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(moon.name));
    await tester.pumpAndSettle();
    expect(find.text(moon.name).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
