import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/comic_reading_stats_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  final book = Book(name: '同名漫画', sourceId: 'stats', bookUrl: '/book');
  final otherSource = Book.fromJson({...book.toJson(), 'sourceId': 'other'});
  final otherUrl = Book.fromJson({...book.toJson(), 'bookUrl': '/other'});
  final chapter = Chapter(title: '第一话', url: '/c1');
  final now = DateTime(2026, 9, 8, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.toggleShelf(book);
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'stats',
        'name': '统计源',
        'rules': <String, dynamic>{},
      }),
    );
  });

  tearDown(() => state.dispose());

  Future<void> record(Book target, int minutes) => state.readingStats.record(
    target,
    chapter,
    from: now.subtract(Duration(minutes: minutes)),
    to: now,
  );

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

  Future<void> openStats(WidgetTester tester) async {
    await tester.longPress(find.byType(BookCover).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('阅读统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读统计'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicReadingStatsScreen), findsOneWidget);
    expect(find.text('单本阅读统计'), findsOneWidget);
  }

  testWidgets('书架长按直达该书统计，区分同名漫画的来源和链接，返回时关闭菜单', (tester) async {
    await record(book, 3);
    await record(otherSource, 20);
    await record(otherUrl, 40);
    await showShelf(tester);
    await openStats(tester);

    expect(find.byType(Card), findsOneWidget);
    expect(find.text(book.name), findsOneWidget);
    expect(find.text('统计源'), findsOneWidget);
    expect(find.text('3 分钟'), findsOneWidget);
    expect(find.text('1 话'), findsOneWidget);
    expect(find.text('1 次阅读'), findsOneWidget);
    expect(find.text('最近阅读：2026-09-08 12:00'), findsOneWidget);
    expect(find.text('20 分钟'), findsNothing);
    expect(find.text('40 分钟'), findsNothing);
    expect(state.readingStats.total.duration, const Duration(minutes: 63));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ShelfScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(BookCover), findsOneWidget);
    expect(state.shelf.single.bookUrl, book.bookUrl);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('该书无记录时显示专属空态，新增或更新记录后实时刷新且始终只显示该书', (tester) async {
    await record(otherSource, 20);
    await record(otherUrl, 40);
    await showShelf(tester);
    await openStats(tester);

    expect(find.text('这本漫画还没有阅读统计'), findsOneWidget);
    expect(find.textContaining('开始阅读《${book.name}》后'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(state.readingStats.forBook(book), isNull);

    await record(otherSource, 5);
    await tester.pumpAndSettle();
    expect(find.text('这本漫画还没有阅读统计'), findsOneWidget);
    await record(book, 2);
    await tester.pumpAndSettle();
    expect(find.text('这本漫画还没有阅读统计'), findsNothing);
    expect(find.text('2 分钟'), findsOneWidget);
    expect(find.text('1 次阅读'), findsOneWidget);

    await state.readingStats.record(
      book,
      Chapter(title: '第二话', url: '/c2'),
      from: now,
      to: now.add(const Duration(minutes: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('3 分钟'), findsOneWidget);
    expect(find.text('2 话'), findsOneWidget);
    expect(find.text('2 次阅读'), findsOneWidget);
    expect(find.text('最近阅读：2026-09-08 12:01'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('来源缺失仍可从书架查看本地统计，窄屏大字号菜单和数据可滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.toggleShelf(book);
    await state.toggleShelf(otherSource);
    await record(otherSource, 20);
    await showShelf(tester, textScale: 2);
    await openStats(tester);

    await tester.scrollUntilVisible(find.text('来源已移除'), 160);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('20 分钟'), 160);
    await tester.pumpAndSettle();
    expect(find.text('20 分钟').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(find.text('最近阅读：2026-09-08 12:00'), 160);
    await tester.pumpAndSettle();
    expect(find.text('最近阅读：2026-09-08 12:00').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
