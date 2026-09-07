import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(String version, {String id = 'search-source'}) =>
    ComicSource.fromJson({
      'id': id,
      'name': '源$version',
      'url': 'https://$version.example.com',
      'rules': {
        'searchUrl': '/search?q=searchKey',
        'searchList': '.book',
        'searchName': 'a@text',
        'searchBookUrl': 'a@href',
      },
    });

String _page(String name) =>
    '<div class="book"><a href="/book">$name</a></div>';

void main() {
  late AppState state;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source('old'));
    respond = (uri) => _page(uri.host.startsWith('old') ? '旧版结果' : '新版结果');
    fetcher = FakeFetcher((uri) => respond(uri));
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  Future<void> search(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SearchScreen(state: state)));
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  void expectReadyToSearch(WidgetTester tester) {
    expect(find.text('漫画源已更新'), findsOneWidget);
    expect(find.text('重新搜索'), findsOneWidget);
    expect(find.text('旧版结果'), findsNothing);
    expect(find.text('暂时无法连接漫画源'), findsNothing);
    expect(find.textContaining('源old'), findsNothing);
    expect(find.textContaining('已聚合'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '海贼王',
    );
  }

  for (final fails in [false, true]) {
    testWidgets('已完成的${fails ? '失败' : '成功'}搜索在编辑源后失效，使用新定义重搜', (tester) async {
      if (fails) respond = (_) => throw FetchException('old failure');
      await search(tester);
      await tester.pumpAndSettle();
      expect(find.text(fails ? '暂时无法连接漫画源' : '旧版结果'), findsOneWidget);

      await state.addSourceManual(_source('new'));
      await tester.pump();
      expect(find.text('旧版结果'), findsNothing);
      await tester.pumpAndSettle();
      expectReadyToSearch(tester);
      expect(fetcher.requests, hasLength(1));

      respond = (_) => _page('新版结果');
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();
      expect(fetcher.requests.last.host, 'new.example.com');
      expect(fetcher.requests.last.queryParameters['q'], '海贼王');
      expect(find.text('新版结果'), findsOneWidget);
      expect(find.text('源: 源new'), findsOneWidget);
      expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
      expect(state.searchHistory, ['海贼王']);
    });

    testWidgets('搜索期间编辑源，旧${fails ? '失败' : '成功'}晚到不覆盖重搜结果', (tester) async {
      final oldResponse = Completer<String>();
      respond = (uri) =>
          uri.host.startsWith('old') ? oldResponse.future : _page('新版结果');
      await search(tester);
      expect(find.text('正在聚合 1 个源'), findsOneWidget);

      await state.addSourceManual(_source('new'));
      await tester.pumpAndSettle();
      expectReadyToSearch(tester);
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();

      if (fails) {
        oldResponse.completeError(FetchException('old failure'));
      } else {
        oldResponse.complete(_page('旧版结果'));
      }
      await tester.pumpAndSettle();
      expect(find.text('新版结果'), findsOneWidget);
      expect(find.text('旧版结果'), findsNothing);
      expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
      expect(find.textContaining('失败'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final remove in [false, true]) {
    testWidgets('搜索中${remove ? '删除' : '停用'}唯一源，显示管理入口，恢复源后可重搜', (tester) async {
      final pending = Completer<String>();
      respond = (_) => pending.future;
      await search(tester);
      final source = state.sources.single;
      if (remove) {
        await state.removeSource(source.id);
      } else {
        await state.toggleSource(source.id);
      }
      pending.complete(_page('旧版结果'));
      await tester.pumpAndSettle();
      expect(find.text('暂无可搜索的源'), findsOneWidget);
      expect(find.text('管理源'), findsOneWidget);
      expect(find.text('旧版结果'), findsNothing);

      if (remove) {
        await state.addSourceManual(_source('new'));
      } else {
        await state.toggleSource(source.id);
      }
      await tester.pumpAndSettle();
      expectReadyToSearch(tester);
      respond = (_) => _page('新版结果');
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();
      expect(find.text('新版结果'), findsOneWidget);
    });
  }

  testWidgets('新增启用源后提示重搜，新的聚合范围包含两个源', (tester) async {
    await search(tester);
    await tester.pumpAndSettle();
    await state.addSourceManual(_source('new', id: 'second-source'));
    await tester.pumpAndSettle();
    expectReadyToSearch(tester);
    await tester.tap(find.text('重新搜索'));
    await tester.pumpAndSettle();
    expect(find.text('已聚合 2 个源 · 2 成功'), findsOneWidget);
    expect(find.text('旧版结果'), findsOneWidget);
    expect(find.text('新版结果'), findsOneWidget);
  });

  testWidgets('健康回报、收藏和无关源编辑不清空在途或已完成结果', (tester) async {
    final unrelated = _source('unused', id: 'unused')..enabled = false;
    await state.addSourceManual(unrelated);
    final pending = Completer<String>();
    respond = (_) => pending.future;
    await search(tester);
    await state.reportSourceHealth(const [], {'search-source': 'temporary'});
    await tester.pump();
    expect(find.text('正在聚合 1 个源'), findsOneWidget);
    expect(find.text('漫画源已更新'), findsNothing);

    pending.complete(_page('旧版结果'));
    await tester.pumpAndSettle();
    await state.toggleShelf(
      Book(name: '旧版结果', bookUrl: 'https://old.example.com/book'),
    );
    await state.reportSourceHealth(const [], {'search-source': 'temporary'});
    await state.addSourceManual(
      _source('unused-new', id: 'unused')..enabled = false,
    );
    await tester.pumpAndSettle();
    expect(find.text('旧版结果'), findsOneWidget);
    expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
    expect(find.text('漫画源已更新'), findsNothing);
    expect(fetcher.requests, hasLength(1));
  });

  testWidgets('替换 AppState 后使用新的源列表，旧状态通知不再影响搜索', (tester) async {
    await search(tester);
    await tester.pumpAndSettle();
    final replacement = AppState();
    addTearDown(replacement.dispose);
    await replacement.addSourceManual(_source('new'));
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(state: replacement)),
    );
    await tester.pumpAndSettle();
    expectReadyToSearch(tester);
    await tester.tap(find.text('重新搜索'));
    await tester.pumpAndSettle();
    await state.removeSource('search-source');
    await tester.pumpAndSettle();
    expect(find.text('新版结果'), findsOneWidget);
    expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
