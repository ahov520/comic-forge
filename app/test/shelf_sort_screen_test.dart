import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_sort.dart';
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
    await tester.pumpAndSettle();
  }

  List<String> gridTitles(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(SliverGrid), matching: find.byType(Text)),
      )
      .map((text) => text.data ?? '')
      .where((name) => name.isNotEmpty)
      .toList();

  Future<void> chooseSort(WidgetTester tester, String label) async {
    await tester.tap(
      find.byTooltip('排序：${state.shelfSort.label}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
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

  testWidgets('排序作用于分组、连载状态和搜索之后的列表，并跨重启保留', (tester) async {
    final group = await state.shelfGroups.create('追更');
    await state.shelfGroups.assign(moon.bookUrl, [group]);
    await state.shelfGroups.assign(extra.bookUrl, [group]);
    await showShelf(tester);
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追更').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pumpAndSettle();
    expect(gridTitles(tester), [extra.name]);

    await chooseSort(tester, '书名');
    expect(gridTitles(tester), [extra.name]);
    expect(state.shelfGroups.filter, group);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已完结')).selected,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'alice',
    );

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.shelfSort, ShelfSort.title);
    expect(
      restored
          .shelfBooks(query: 'alice', kindFilter: 2)
          .map((book) => book.name),
      [extra.name],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('切换排序后从顶部展示，窄屏大字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var i = 0; i < 24; i++) {
      await state.toggleShelf(Book(name: '合辑 $i', bookUrl: '/collection-$i'));
    }
    await showShelf(tester, textScale: 2);
    await tester.scrollUntilVisible(
      find.text('合辑 23'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(moon.name).hitTestable(), findsNothing);
    await chooseSort(tester, '书名');
    expect(
      find
          .descendant(of: find.byType(SliverGrid), matching: find.text(moon.name))
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(BookCover).evaluate().length, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
