import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

class _DetailRuntime extends SourceRuntime {
  _DetailRuntime(ComicSource source, this.loadDetail)
    : super(source: source, fetcher: FakeFetcher((_) => ''));

  final Future<(Book, List<Chapter>)> Function(String) loadDetail;

  @override
  Future<(Book, List<Chapter>)> detail(String bookUrl) => loadDetail(bookUrl);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late ComicSource source;
  late SourceService service;

  Book book(String id, {String latest = ''}) => Book(
    sourceId: source.id,
    name: '漫画 $id',
    bookUrl: 'https://shelf.example/$id',
    lastChapter: latest,
  );

  List<Chapter> chapters(int count) => List.generate(
    count,
    (i) => Chapter(title: '第${i + 1}话', url: 'https://shelf.example/c${i + 1}'),
  );

  Future<void> read(Book book, List<Chapter> chapters, int index) =>
      state.saveProgress(
        book,
        chapterUrl: chapters[index].url,
        chapterTitle: chapters[index].title,
        chapterIndex: index,
        chapterCount: chapters.length,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = SourceService.instance;
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'shelf-updates',
      'name': '书架源',
      'url': 'https://shelf.example',
      'rules': <String, dynamic>{},
    });
    await state.addSourceManual(source);
    service.debugClearSwitchCache();
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  test('按章节链接计算未读，插入早期章节不误增未读，读到末话后消失', () async {
    final b = book('one');
    await state.toggleShelf(b);
    expect(state.shelfUpdateFor(b), isNull);
    final list = chapters(4);
    await state.saveDetailCache(b, list);
    expect(state.shelfUpdateFor(b)?.unreadCount, 4);
    await read(b, list, 1);
    expect(state.shelfUpdateFor(b)?.unreadCount, 2);
    await state.saveDetailCache(b, [
      Chapter(title: '序章', url: '/intro'),
      ...list,
    ]);
    expect(state.shelfUpdateFor(b)?.unreadCount, 2);
    await read(b, list, 3);
    expect(state.shelfUpdateFor(b), isNull);
  });

  test('只有最新话标题时归一化更新前缀，不虚构未读数量', () async {
    final b = book('title', latest: '更新至 第 2 话');
    await state.toggleShelf(b);
    expect(state.shelfUpdateFor(b)?.label, '未读');
    await read(b, chapters(2), 1);
    expect(state.shelfUpdateFor(b), isNull);
    b.lastChapter = '最新：第3话';
    expect(state.shelfUpdateFor(b)?.label, '更新');
    expect(state.shelfUpdateFor(b)?.unreadCount, isNull);
    await state.saveDetailCache(b, [
      Chapter(title: '第3话', url: '/changed-url'),
    ]);
    expect(state.shelfUpdateFor(b)?.unreadCount, isNull);
  });

  test('清除跨重启保留且不修改进度，同名新话链接仍重新提醒', () async {
    final b = book('persist');
    final list = chapters(3);
    await state.toggleShelf(b);
    await state.saveDetailCache(b, list);
    await read(b, list, 0);
    final progress = state.progressFor(b.bookUrl)!;
    await state.clearShelfUpdate(b);
    expect(state.shelfUpdateFor(b), isNull);
    expect(state.progressFor(b.bookUrl), same(progress));

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.shelfUpdateFor(restored.shelf.single), isNull);
    expect(restored.progressFor(b.bookUrl)?.toJson(), progress.toJson());
    await restored.saveDetailCache(b, [
      ...list,
      Chapter(title: list.last.title, url: '/new-chapter'),
    ]);
    expect(restored.shelfUpdateFor(restored.shelf.single)?.unreadCount, 3);
  });

  test('详情缓存被淘汰后仍能跨重启计算书架未读，全部清除只清提醒', () async {
    final a = book('a');
    final b = book('b');
    for (final item in [a, b]) {
      await state.toggleShelf(item);
      await state.saveDetailCache(item, chapters(3));
      await read(item, chapters(3), 0);
    }
    await (await SharedPreferences.getInstance()).remove('cf.detailCache');
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.detailCache, isEmpty);
    expect(restored.shelfUpdateFor(a)?.unreadCount, 2);
    await restored.clearShelfUpdates();
    expect(restored.shelf.map(restored.shelfUpdateFor), everyElement(isNull));
    expect(restored.progress.length, 2);
    await restored.toggleShelf(a);
    await restored.toggleShelf(a);
    expect(restored.shelfUpdateFor(b), isNull);
  });

  test('按选中漫画清除角标，其它书与阅读进度不变', () async {
    final a = book('a');
    final b = book('b');
    for (final item in [a, b]) {
      await state.toggleShelf(item);
      await state.saveDetailCache(item, chapters(3));
      await read(item, chapters(3), 0);
    }
    await state.clearShelfUpdatesFor([a, a]);
    expect(state.shelfUpdateFor(a), isNull);
    expect(state.shelfUpdateFor(b)?.unreadCount, 2);
    expect(state.progressFor(a.bookUrl)?.chapterIndex, 0);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.shelfUpdateFor(a), isNull);
    expect(restored.shelfUpdateFor(b)?.unreadCount, 2);
  });

  test('部分刷新失败保留旧目录，重复检查共用请求，移除的书不复活', () async {
    final a = book('ok');
    final b = book('fail');
    final removed = book('removed');
    final disabled = Book(
      name: '无源',
      bookUrl: '/disabled',
      sourceId: 'missing',
    );
    for (final item in [a, b, removed, disabled]) {
      await state.toggleShelf(item);
      await state.saveDetailCache(item, chapters(2));
    }
    final pending = Completer<(Book, List<Chapter>)>();
    final calls = <String>[];
    service.debugRuntimeOverride = (s) => _DetailRuntime(s, (url) async {
      calls.add(url);
      if (url == b.bookUrl) throw StateError('offline');
      if (url == removed.bookUrl) return pending.future;
      return (a, chapters(4));
    });
    final first = state.refreshShelfUpdates();
    expect(state.checkingShelfUpdates, isTrue);
    expect(state.refreshShelfUpdates(), same(first));
    await state.toggleShelf(removed);
    pending.complete((removed, chapters(5)));
    expect(await first, (checked: 1, failed: 1, skipped: 2));
    expect(state.checkingShelfUpdates, isFalse);
    expect(calls.length, 3);
    expect(state.shelfUpdateFor(a)?.unreadCount, 4);
    expect(state.shelfUpdateFor(b)?.unreadCount, 2);
    expect(state.inShelf(removed), isFalse);
  });

  testWidgets('封面显示未读，长按清除单本，新话到来后菜单清除全部', (tester) async {
    final b = book('badge');
    await state.toggleShelf(b);
    await state.saveDetailCache(b, chapters(3));
    await read(b, chapters(3), 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    expect(find.text('未读 2'), findsOneWidget);
    await tester.longPress(find.byType(BookCover));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除更新角标'));
    await tester.pumpAndSettle();
    expect(find.text('未读 2'), findsNothing);
    expect(state.progressFor(b.bookUrl)?.chapterIndex, 0);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();

    await state.saveDetailCache(b, chapters(4));
    await tester.pumpAndSettle();
    expect(find.text('未读 3'), findsOneWidget);
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除全部更新角标'));
    await tester.pumpAndSettle();
    expect(find.text('未读 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检查更新入口刷新封面并反馈失败数量', (tester) async {
    final b = book('refresh');
    await state.toggleShelf(b);
    service.debugRuntimeOverride = (s) =>
        _DetailRuntime(s, (_) async => (b, chapters(5)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    await tester.tap(find.byTooltip('检查书架更新'));
    await tester.pumpAndSettle();
    expect(find.text('未读 5'), findsOneWidget);
    expect(find.text('已检查 1 本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
