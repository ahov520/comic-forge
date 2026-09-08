import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_sort.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
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
    updateTime: '2024-01-01',
  );
  final mountain = Book(
    name: '山海卷',
    author: 'Alice',
    kind: '已完结',
    bookUrl: '/mountain',
    updateTime: '2024-03-01',
  );
  final extra = Book(
    name: 'Moon 番外',
    author: 'Alice',
    kind: '已完结',
    bookUrl: '/extra',
    updateTime: '2024-02-01',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    for (final book in [moon, mountain, extra]) {
      await state.toggleShelf(book);
    }
    state.progress[moon.bookUrl] = ReadingProgress(
      bookUrl: moon.bookUrl,
      sourceId: '',
      chapterUrl: '/c',
      chapterTitle: '',
      chapterIndex: 0,
      chapterCount: 1,
      at: 30,
    );
    state.progress[extra.bookUrl] = ReadingProgress(
      bookUrl: extra.bookUrl,
      sourceId: '',
      chapterUrl: '/c',
      chapterTitle: '',
      chapterIndex: 0,
      chapterCount: 1,
      at: 20,
    );
    state.progress[mountain.bookUrl] = ReadingProgress(
      bookUrl: mountain.bookUrl,
      sourceId: '',
      chapterUrl: '/c',
      chapterTitle: '',
      chapterIndex: 0,
      chapterCount: 1,
      at: 10,
    );
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
    await tester.pump();
  }

  List<String> gridTitles(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(SliverGrid), matching: find.byType(Text)),
      )
      .map((text) => text.data ?? '')
      .where((name) => name.isNotEmpty)
      .toList();

  Future<void> settleMenu(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> chooseSort(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byTooltip('排序：${state.shelfSort.label}'));
    await settleMenu(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<ShelfSort>, label));
    await settleMenu(tester);
  }

  testWidgets('默认最近阅读，可改为更新时间、书名和作者', (tester) async {
    await showShelf(tester);
    expect(gridTitles(tester), [moon.name, extra.name, mountain.name]);

    await chooseSort(tester, '更新时间');
    expect(state.shelfSort, ShelfSort.updateTime);
    expect(gridTitles(tester), [mountain.name, extra.name, moon.name]);

    await chooseSort(tester, '书名');
    expect(gridTitles(tester), [moon.name, extra.name, mountain.name]);

    await chooseSort(tester, '作者');
    expect(gridTitles(tester), [extra.name, mountain.name, moon.name]);
    expect(find.byTooltip('排序：作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排序作用于连载状态筛选之后的列表', (tester) async {
    await showShelf(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pump();
    expect(gridTitles(tester), [extra.name, mountain.name]);

    await chooseSort(tester, '更新时间');
    expect(gridTitles(tester), [mountain.name, extra.name]);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已完结')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('切换排序后列表回到顶部', (tester) async {
    for (var i = 0; i < 12; i++) {
      await state.toggleShelf(Book(name: '合辑 $i', bookUrl: '/collection-$i'));
    }
    await showShelf(tester);
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(24);
    await tester.pump();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 24);
    await chooseSort(tester, '书名');
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(
      find
          .descendant(of: find.byType(SliverGrid), matching: find.text(moon.name))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字号可打开排序菜单且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showShelf(tester, textScale: 2);
    await chooseSort(tester, '书名');
    expect(state.shelfSort, ShelfSort.title);
    expect(gridTitles(tester), [moon.name, extra.name, mountain.name]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
