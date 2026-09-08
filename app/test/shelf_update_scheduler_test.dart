import 'dart:async';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_update_schedule.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

class _DetailRuntime extends SourceRuntime {
  _DetailRuntime(ComicSource source, this.loadDetail)
    : super(source: source, fetcher: FakeFetcher((_) => ''));

  final Future<(Book, List<Chapter>)> Function() loadDetail;

  @override
  Future<(Book, List<Chapter>)> detail(String bookUrl) => loadDetail();
}

void main() {
  late ComicSource source;
  late Book book;
  late int calls;
  late Future<(Book, List<Chapter>)> Function() loadDetail;
  final service = SourceService.instance;

  List<Chapter> chapters(int count) => List.generate(
    count,
    (i) => Chapter(title: '第${i + 1}话', url: 'https://schedule.example/c$i'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = ComicSource.fromJson({
      'id': 'scheduled-shelf',
      'name': '定时更新源',
      'url': 'https://schedule.example',
      'rules': <String, dynamic>{},
    });
    book = Book(
      name: '定时漫画',
      sourceId: source.id,
      bookUrl: 'https://schedule.example/book',
    );
    calls = 0;
    loadDetail = () async => (book, chapters(3));
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (s) => _DetailRuntime(s, () {
      calls++;
      return loadDetail();
    });
  });

  tearDown(() {
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<AppState> openApp(
    WidgetTester tester, {
    bool enabled = true,
    bool withBook = true,
    AppLifecycleState lifecycle = AppLifecycleState.resumed,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(lifecycle);
    final state = AppState(
      shelfUpdateSchedule: ShelfUpdateSchedule(now: tester.binding.clock.now),
    );
    addTearDown(state.dispose);
    await state.addSourceManual(source);
    if (withBook) await state.toggleShelf(book);
    await state.shelfUpdateSchedule.setInterval(ShelfUpdateInterval.hourly);
    await state.shelfUpdateSchedule.setEnabled(enabled);
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('启动到期检查和前台计时复用目录刷新，未读角标随新话变化', (tester) async {
    final state = await openApp(tester);
    expect(calls, 1);
    expect(find.text('未读 3'), findsOneWidget);
    await state.saveProgress(
      book,
      chapterUrl: chapters(3).first.url,
      chapterTitle: '第1话',
      chapterIndex: 0,
      chapterCount: 3,
    );
    await tester.pump();
    expect(find.text('未读 2'), findsOneWidget);
    await state.clearShelfUpdate(book);
    loadDetail = () async => (book, chapters(5));
    await tester.pump(const Duration(minutes: 59));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('未读 4'), findsOneWidget);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 0);
    await closeApp(tester);
  });

  testWidgets('关闭时不检查，启用与关闭立即重排，间隔缩短后补查', (tester) async {
    final state = await openApp(tester, enabled: false);
    await tester.pump(const Duration(days: 1));
    expect(calls, 0);
    await state.shelfUpdateSchedule.setEnabled(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await state.shelfUpdateSchedule.setInterval(ShelfUpdateInterval.daily);
    await tester.pump(const Duration(hours: 2));
    expect(calls, 1);
    await state.shelfUpdateSchedule.setInterval(ShelfUpdateInterval.hourly);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await state.shelfUpdateSchedule.setEnabled(false);
    await tester.pump(const Duration(days: 2));
    expect(calls, 2);
    await closeApp(tester);
  });

  testWidgets('后台暂停计时，恢复前台只补查一次，未到期不重复', (tester) async {
    await openApp(tester);
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 3));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await closeApp(tester);
    await tester.pump(const Duration(days: 1));
    expect(calls, 2);
  });

  testWidgets('后台启动不检查，空书架不轮询，加入漫画后检查', (tester) async {
    final state = await openApp(
      tester,
      withBook: false,
      lifecycle: AppLifecycleState.paused,
    );
    await tester.pump(const Duration(days: 1));
    expect(calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await state.toggleShelf(book);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await closeApp(tester);
  });

  testWidgets('手动检查与到期检查共享在途请求，失败保留角标并节流', (tester) async {
    final state = await openApp(tester, withBook: false);
    await state.toggleShelf(book);
    await state.saveDetailCache(book, chapters(2));
    final pending = Completer<(Book, List<Chapter>)>();
    loadDetail = () => pending.future;
    final manual = state.refreshShelfUpdates();
    expect(state.refreshShelfUpdates(), same(manual));
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(await manual, (checked: 0, failed: 1, skipped: 0));
    expect(find.text('未读 2'), findsOneWidget);
    await tester.pump(const Duration(minutes: 30));
    expect(calls, 1);
    loadDetail = () async => (book, chapters(4));
    await tester.pump(const Duration(minutes: 30));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('未读 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeApp(tester);
  });

  testWidgets('重建应用从持久化的最近检查时间继续等待', (tester) async {
    final state = await openApp(tester);
    expect(calls, 1);
    final checkedAt = state.shelfUpdateSchedule.lastCheckedAt;
    await closeApp(tester);
    await tester.pump(const Duration(minutes: 20));
    final restored = AppState(
      shelfUpdateSchedule: ShelfUpdateSchedule(now: tester.binding.clock.now),
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.shelfUpdateSchedule.lastCheckedAt, checkedAt);
    await tester.pumpWidget(ComicForgeApp(state: restored));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 40));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await closeApp(tester);
  });

  testWidgets('卸载应用时取消计时，在途刷新完成后不会重新启动', (tester) async {
    final pending = Completer<(Book, List<Chapter>)>();
    loadDetail = () => pending.future;
    final state = await openApp(tester, withBook: false);
    await state.toggleShelf(book);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await closeApp(tester);
    pending.complete((book, chapters(3)));
    await tester.pump();
    await tester.pump(const Duration(days: 1));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
