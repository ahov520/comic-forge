import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/comic_reading_stats_screen.dart';
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

  Future<void> showDetail(
    WidgetTester tester, {
    Book? shown,
    List<Chapter>? chapters,
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
          detailLoaderOverride: (_) async => (target, chapters ?? [chapter]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openStats(WidgetTester tester) async {
    final entry = find.byKey(const Key('detail-reading-stats'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ComicReadingStatsScreen), findsOneWidget);
    expect(find.text('单本阅读统计'), findsOneWidget);
    final screen = tester.widget<ComicReadingStatsScreen>(
      find.byType(ComicReadingStatsScreen),
    );
    expect(screen.stats, state.readingStats);
    expect(screen.book?.sourceId, book.sourceId);
    expect(screen.book?.bookUrl, book.bookUrl);
    expect(screen.sources, state.sources);
  }

  testWidgets('详情页入口直达该书统计，区分同名漫画的来源和链接，返回后仍在详情', (
    tester,
  ) async {
    await record(book, 3);
    await record(otherSource, 20);
    await record(otherUrl, 40);
    await showDetail(tester);
    expect(find.text('阅读统计'), findsOneWidget);
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
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.byType(ComicReadingStatsScreen), findsNothing);
    expect(find.byKey(const Key('detail-reading-stats')), findsOneWidget);
    expect(find.text('第一话'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('该书无记录时显示专属空态，新增或更新记录后实时刷新且始终只显示该书', (
    tester,
  ) async {
    await record(otherSource, 20);
    await record(otherUrl, 40);
    await showDetail(tester);
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

  testWidgets('空目录与源停用仍可进入统计，窄屏大字号入口和数据可滚动', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await record(book, 20);
    await state.saveDetailCache(book, const []);
    await state.toggleSource('stats');
    await showDetail(tester, chapters: const [], textScale: 2);

    expect(find.text('暂无章节'), findsOneWidget);
    expect(find.byKey(const Key('detail-reading-stats')), findsOneWidget);
    await openStats(tester);

    await tester.scrollUntilVisible(find.text('统计源'), 160);
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
