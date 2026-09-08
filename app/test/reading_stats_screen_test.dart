import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_stats.dart';
import 'package:comic_forge/ui/comic_reading_stats_screen.dart';
import 'package:comic_forge/ui/reading_stats_screen.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  late DateTime now;
  final book = Book(name: '统计漫画', sourceId: 'stats', bookUrl: '/book');
  final chapter = Chapter(title: '第一话', url: '/c1');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 8, 12);
    state = AppState(readingStats: ReadingStats(now: () => now));
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'stats',
        'name': '统计源',
        'rules': <String, dynamic>{},
      }),
    );
  });
  tearDown(() => state.dispose());

  Finder cardText(String title, String text) => find.descendant(
    of: find.widgetWithText(Card, title),
    matching: find.text(text),
  );

  for (final brightness in Brightness.values) {
    testWidgets('设置入口展示今日、累计与近七日，窄屏大字号可完整浏览：${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final yesterday = now.subtract(const Duration(days: 1));
      await state.readingStats.record(
        book,
        chapter,
        from: yesterday.subtract(const Duration(minutes: 90)),
        to: yesterday,
      );
      await state.readingStats.record(
        book,
        chapter,
        from: now.subtract(const Duration(minutes: 45)),
        to: now,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: SettingsScreen(state: state)),
        ),
      );
      await tester.scrollUntilVisible(find.text('阅读统计'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读统计'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadingStatsScreen), findsOneWidget);
      expect(cardText('今日阅读', '45 分钟'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('累计阅读'), 160);
      await tester.pumpAndSettle();
      expect(cardText('累计阅读', '2 小时 15 分钟'), findsOneWidget);
      expect(cardText('累计阅读', '1 本漫画'), findsOneWidget);
      expect(cardText('累计阅读', '1 话'), findsOneWidget);
      expect(cardText('累计阅读', '2 天有阅读'), findsOneWidget);
      final todayBar = find.byKey(ValueKey(DateTime(2026, 9, 8)));
      await tester.scrollUntilVisible(todayBar, 160);
      await tester.pumpAndSettle();
      expect(tester.widget<LinearProgressIndicator>(todayBar).value, 0.5);
      await tester.scrollUntilVisible(find.textContaining('统计从此版本开始记录'), 200);
      await tester.pumpAndSettle();
      expect(find.textContaining('统计从此版本开始记录').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('按漫画查看'), -200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('按漫画查看'));
      await tester.pumpAndSettle();
      expect(find.byType(ComicReadingStatsScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.text('统计漫画'), 160);
      await tester.pumpAndSettle();
      expect(find.text('统计源'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('2 次阅读'), 160);
      await tester.pumpAndSettle();
      expect(find.text('2 小时 15 分钟'), findsOneWidget);
      expect(find.text('1 话'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('最近阅读：2026-09-08 12:00'), 160);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('空统计显示零，外部记录实时刷新，跨日回到前台更新今日数据', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(home: ReadingStatsScreen(stats: state.readingStats)),
    );
    expect(cardText('今日阅读', '0 分钟'), findsOneWidget);
    expect(cardText('累计阅读', '0 本漫画'), findsOneWidget);
    await state.readingStats.record(
      book,
      chapter,
      from: now.subtract(const Duration(minutes: 2)),
      to: now,
    );
    await tester.pumpAndSettle();
    expect(cardText('今日阅读', '2 分钟'), findsOneWidget);
    expect(cardText('累计阅读', '1 话'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(days: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cardText('今日阅读', '0 分钟'), findsOneWidget);
    expect(cardText('累计阅读', '2 分钟'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('单本列表区分同名不同来源，按最近阅读排序并实时更新各自的统计', (tester) async {
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'other',
        'name': '另一统计源',
        'rules': <String, dynamic>{},
      }),
    );
    final other = Book.fromJson({...book.toJson(), 'sourceId': 'other'});
    final yesterday = now.subtract(const Duration(days: 1));
    await state.readingStats.record(
      book,
      chapter,
      from: yesterday.subtract(const Duration(minutes: 3)),
      to: yesterday,
    );
    await state.readingStats.record(
      other,
      chapter,
      from: now.subtract(const Duration(minutes: 2)),
      to: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingStatsScreen(
          stats: state.readingStats,
          sources: state.sources,
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('按漫画查看'), 200);
    await tester.tap(find.text('按漫画查看'));
    await tester.pumpAndSettle();
    final firstCard = find.byKey(
      ValueKey(state.readingStats.forBook(book)!.key),
    );
    final otherCard = find.byKey(
      ValueKey(state.readingStats.forBook(other)!.key),
    );
    Finder within(Finder card, String text) =>
        find.descendant(of: card, matching: find.text(text));
    expect(within(firstCard, '统计源'), findsOneWidget);
    expect(within(firstCard, '3 分钟'), findsOneWidget);
    expect(within(otherCard, '另一统计源'), findsOneWidget);
    expect(within(otherCard, '2 分钟'), findsOneWidget);
    expect(
      tester.getTopLeft(otherCard).dy,
      lessThan(tester.getTopLeft(firstCard).dy),
    );
    now = now.add(const Duration(minutes: 1));
    await state.readingStats.record(
      book,
      Chapter(title: '第二话', url: '/c2'),
      from: now.subtract(const Duration(minutes: 1)),
      to: now,
    );
    await tester.pumpAndSettle();
    expect(within(firstCard, '4 分钟'), findsOneWidget);
    expect(within(firstCard, '2 话'), findsOneWidget);
    expect(within(firstCard, '2 次阅读'), findsOneWidget);
    expect(within(firstCard, '最近阅读：2026-09-08 12:01'), findsOneWidget);
    expect(within(otherCard, '1 话'), findsOneWidget);
    expect(within(otherCard, '1 次阅读'), findsOneWidget);
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getTopLeft(otherCard).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空单本统计可进入，未收藏和来源已移除的漫画仍可显示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingStatsScreen(stats: state.readingStats)),
    );
    await tester.scrollUntilVisible(find.text('按漫画查看'), 200);
    await tester.tap(find.text('按漫画查看'));
    await tester.pumpAndSettle();
    expect(find.text('还没有单本阅读统计'), findsOneWidget);
    expect(find.textContaining('之前的阅读仍保留在累计统计中'), findsOneWidget);
    final unnamed = Book(sourceId: 'removed', bookUrl: '/unnamed');
    await state.readingStats.record(
      unnamed,
      chapter,
      from: now.subtract(const Duration(seconds: 30)),
      to: now,
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有单本阅读统计'), findsNothing);
    expect(find.text('未命名漫画'), findsOneWidget);
    expect(find.text('来源已移除'), findsOneWidget);
    expect(find.text('不足 1 分钟'), findsOneWidget);
    expect(find.text('1 话'), findsOneWidget);
    expect(find.text('1 次阅读'), findsOneWidget);
    expect(state.shelf, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
