import 'dart:async';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_update_notices.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/fake_shelf_update_notifier.dart';

class _DetailRuntime extends SourceRuntime {
  _DetailRuntime(ComicSource source, this.loadDetail)
    : super(source: source, fetcher: FakeFetcher((_) => ''));

  final Future<(Book, List<Chapter>)> Function(String) loadDetail;

  @override
  Future<(Book, List<Chapter>)> detail(String bookUrl) => loadDetail(bookUrl);
}

void main() {
  late ComicSource source;
  late Book book;
  late int calls;
  late Future<(Book, List<Chapter>)> Function() loadDetail;
  late FakeShelfUpdateNotifier notifier;
  final service = SourceService.instance;

  List<Chapter> chapters(int count) => List.generate(
    count,
    (i) => Chapter(title: '第${i + 1}话', url: 'https://notify.example/c$i'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = ComicSource.fromJson({
      'id': 'notify-shelf',
      'name': '通知源',
      'url': 'https://notify.example',
      'rules': <String, dynamic>{},
    });
    book = Book(
      name: '通知漫画',
      sourceId: source.id,
      bookUrl: 'https://notify.example/book',
    );
    calls = 0;
    loadDetail = () async => (book, chapters(3));
    notifier = FakeShelfUpdateNotifier();
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (s) => _DetailRuntime(s, (_) {
      calls++;
      return loadDetail();
    });
  });

  tearDown(() {
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<AppState> makeState() async {
    final state = AppState(updateNotifier: notifier);
    addTearDown(state.dispose);
    await state.addSourceManual(source);
    await state.toggleShelf(book);
    return state;
  }

  test('关闭通知时检查新话不展示，开启后也不补发同一话', () async {
    final state = await makeState();
    await state.saveDetailCache(book, chapters(3));
    loadDetail = () async => (book, chapters(5));
    await state.refreshShelfUpdates();
    expect(calls, 1);
    expect(notifier.shown, isEmpty);

    await state.setUpdateNotificationsEnabled(true);
    await state.refreshShelfUpdates();
    expect(notifier.shown, isEmpty);

    loadDetail = () async => (book, chapters(6));
    await state.refreshShelfUpdates();
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.badge.latestTitle, '第6话');
    expect(notifier.shown.single.badge.unreadCount, 6);

    await state.refreshShelfUpdates();
    expect(notifier.shown, hasLength(1));
  });

  test('首次拉目录不通知，之后新章节才通知', () async {
    final state = await makeState();
    await state.setUpdateNotificationsEnabled(true);
    await state.refreshShelfUpdates();
    expect(calls, 1);
    expect(notifier.shown, isEmpty);

    loadDetail = () async => (book, chapters(4));
    await state.refreshShelfUpdates();
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.badge.unreadCount, 4);
  });

  test('拒绝权限时保持关闭；关闭通知会撤掉已发条目', () async {
    notifier.permissionGranted = false;
    final state = await makeState();
    expect(await state.setUpdateNotificationsEnabled(true), isFalse);
    expect(state.updateNotifications.enabled, isFalse);
    await state.saveDetailCache(book, chapters(2));
    loadDetail = () async => (book, chapters(3));
    await state.refreshShelfUpdates();
    expect(notifier.shown, isEmpty);

    notifier.permissionGranted = true;
    expect(await state.setUpdateNotificationsEnabled(true), isTrue);
    loadDetail = () async => (book, chapters(4));
    await state.refreshShelfUpdates();
    expect(notifier.shown, hasLength(1));
    expect(await state.setUpdateNotificationsEnabled(false), isTrue);
    expect(notifier.cancelAllCount, 1);
    expect(notifier.shown, isEmpty);
  });

  testWidgets('点按通知打开对应漫画详情', (tester) async {
    final state = await makeState();
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsNothing);

    notifier.tap(
      ShelfUpdateOpenRequest(bookUrl: book.bookUrl, sourceId: source.id),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('通知漫画'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冷启动携带打开请求时进入该书详情', (tester) async {
    notifier.launchRequest = ShelfUpdateOpenRequest(
      bookUrl: book.bookUrl,
      sourceId: source.id,
    );
    final state = await makeState();
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('通知漫画'), findsWidgets);
  });
}
