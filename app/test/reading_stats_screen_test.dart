import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_stats.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 8, 12);
    state = AppState(readingStats: ReadingStats(now: () => now));
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
}
