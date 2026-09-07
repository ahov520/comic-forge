import 'package:comic_forge/main.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });

  tearDown(() => state.dispose());

  for (final width in [320.0, 412.0]) {
    testWidgets('手机宽度 $width 大字号下保留三列封面，空分类可恢复并打开漫画', (tester) async {
      tester.view.physicalSize = Size(width, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (var i = 0; i < 6; i++) {
        await state.toggleShelf(
          Book(
            name: '很长的漫画名称与番外篇 $i',
            kind: '连载中',
            bookUrl: 'https://example.com/book/$i',
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ShelfScreen(state: state, onExplore: () {}),
          ),
        ),
      );
      final covers = find.byType(BookCover);
      final first = tester.getRect(covers.at(0));
      final third = tester.getRect(covers.at(2));
      final fourth = tester.getRect(covers.at(3));
      expect(first.top, third.top);
      expect(first.top, lessThan(fourth.top));
      expect(first.left, fourth.left);

      await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();
      expect(find.text('这个分类还没有漫画'), findsNothing);
      await tester.tap(find.byType(BookCover).first);
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('空书架保留页头，探索按钮切换到对应导航页', (tester) async {
    await tester.pumpWidget(ComicForgeApp(state: state));

    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.text('书架还没有漫画'), findsOneWidget);
    await tester.tap(find.text('去探索'));
    await tester.pumpAndSettle();

    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byType(ShelfScreen), findsNothing);
  });

  testWidgets('筛选条与标题左对齐，距封面 12，标签在胶囊内居中', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );

    final title = tester.getRect(find.text('书架'));
    final allChip = find.widgetWithText(ChoiceChip, '全部');
    final serialChip = find.widgetWithText(ChoiceChip, '连载中');
    final allRect = tester.getRect(allChip);
    final serialRect = tester.getRect(serialChip);
    final allLabel = tester.getRect(find.text('全部'));

    expect(find.byType(FilterChipRow), findsOneWidget);
    expect(allRect.left, closeTo(title.left, 0.5));
    expect(allRect.center.dy, closeTo(serialRect.center.dy, 0.5));
    expect(allRect.height, lessThan(40));
    expect(allLabel.center.dx, closeTo(allRect.center.dx, 1.5));
    expect(allLabel.center.dy, closeTo(allRect.center.dy, 1.5));
    expect(find.text('书架还没有漫画'), findsOneWidget);
    expect(find.text('去探索'), findsOneWidget);

    await state.toggleShelf(
      Book(
        name: '海贼王',
        kind: '连载中',
        bookUrl: 'https://example.com/book/one-piece',
      ),
    );
    await tester.pumpAndSettle();

    final cover = tester.getRect(find.byType(BookCover).first);
    expect(cover.left, closeTo(title.left, 0.5));
    expect(
      cover.top - tester.getRect(allChip).bottom,
      closeTo(FilterChipRow.padding.bottom, 1.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('空分类可恢复全部藏书，移除最后一本后显示收藏引导', (tester) async {
    final book = Book(
      name: '测试漫画',
      kind: '连载中',
      bookUrl: 'https://example.com/book/1',
    );
    await state.toggleShelf(book);
    await tester.pumpWidget(ComicForgeApp(state: state));

    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有漫画'), findsOneWidget);
    expect(find.text(book.name), findsNothing);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text(book.name), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部')).selected,
      isTrue,
    );

    await state.toggleShelf(book);
    await tester.pumpAndSettle();
    expect(find.text('书架还没有漫画'), findsOneWidget);
    expect(find.text('去探索'), findsOneWidget);
    expect(find.text('查看全部'), findsNothing);
  });
}
