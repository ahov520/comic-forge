import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/search_filters.dart';
import 'package:comic_forge/ui/search_filter_sheet.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  late AppState state;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri) respond;
  String page(String name) =>
      '<div class="book"><a href="/book">$name</a></div>';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    for (final id in ['a', 'b', 'c']) {
      await state.addSourceManual(
        ComicSource.fromJson({
          'id': id,
          'name': '源$id',
          'url': 'https://$id.example',
          'rules': {
            'searchUrl': '/search?q=searchKey',
            'searchList': '.book',
            'searchName': 'a@text',
            'searchBookUrl': 'a@href',
          },
        }),
      );
    }
    state.sources.last.failCount = 3;
    respond = (uri) => page('${uri.host}结果');
    fetcher = FakeFetcher((uri) => respond(uri));
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugRuntimeOverride = (s) =>
        SourceRuntime(source: s, fetcher: fetcher);
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  Future<void> show(WidgetTester tester) =>
      tester.pumpWidget(MaterialApp(home: SearchScreen(state: state)));
  Future<void> search(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '测试漫画');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip('搜索筛选'));
    await tester.pumpAndSettle();
  }

  testWidgets('通过筛选面板组合健康与指定源，只请求选中的可用源', (tester) async {
    await show(tester);
    await openFilters(tester);
    await tester.tap(find.text('仅健康源'));
    await tester.tap(find.text('指定漫画源'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-source-b')));
    await tester.pump();
    expect(find.text('搜索筛选 · 1 个可用源'), findsOneWidget);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(fetcher.requests, isEmpty);
    await search(tester);
    await tester.pumpAndSettle();
    expect(fetcher.requests.map((r) => r.host), ['a.example']);
    expect(find.text('a.example结果'), findsOneWidget);
    expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
    expect(state.sources.every((s) => s.enabled), isTrue);
  });

  testWidgets('搜索中更改筛选自动重搜，旧源晚到的结果不覆盖新范围', (tester) async {
    final pending = Completer<String>();
    respond = (uri) => uri.host == 'a.example' ? pending.future : page('新版结果');
    await state.setSearchFilters(SearchFilters(sourceIds: {'a'}));
    await show(tester);
    await search(tester);
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('search-source-a')));
    await tester.tap(find.byKey(const ValueKey('search-source-b')));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(find.text('新版结果'), findsOneWidget);
    pending.complete(page('旧版结果'));
    await tester.pumpAndSettle();
    expect(find.text('旧版结果'), findsNothing);
    expect(find.text('新版结果'), findsOneWidget);
    expect(fetcher.requests.map((r) => r.host), ['a.example', 'b.example']);
    expect(state.searchHistory, ['测试漫画']);
  });

  testWidgets('健康回报达到失效阈值保留本次成功结果，下次搜索跳过失败源', (tester) async {
    state.sources[1].failCount = 2;
    respond = (uri) =>
        uri.host == 'b.example' ? throw FetchException('failed') : page('成功结果');
    await state.setSearchFilters(SearchFilters(onlyHealthy: true));
    await show(tester);
    await search(tester);
    await tester.pumpAndSettle();
    expect(state.sources[1].failCount, 3);
    expect(find.text('成功结果'), findsOneWidget);
    expect(find.text('已聚合 2 个源 · 1 成功 1 失败'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('已聚合 1 个源 · 1 成功'), findsOneWidget);
    expect(fetcher.requests.where((r) => r.host == 'b.example'), hasLength(1));
  });

  testWidgets('空选择显示调整入口，取消不改变筛选，重置后恢复全部请求', (tester) async {
    await state.setSearchFilters(SearchFilters(sourceIds: {}));
    await show(tester);
    await search(tester);
    await tester.pumpAndSettle();
    expect(find.text('当前筛选下没有可搜索的源'), findsOneWidget);
    expect(fetcher.requests, isEmpty);
    await tester.tap(find.text('调整筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pump();
    Navigator.of(tester.element(find.byType(SearchFilterSheet))).pop();
    await tester.pumpAndSettle();
    expect(state.searchFilters.sourceIds, isEmpty);
    await openFilters(tester);
    await tester.tap(find.text('重置'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(state.searchFilters.isActive, isFalse);
    expect(fetcher.requests.map((r) => r.host).toSet(), {
      'a.example',
      'b.example',
      'c.example',
    });
  });
}
