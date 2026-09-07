import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/explore_results.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

const _root = 'https://paging.example.com';

ComicSource _source({String? entries}) => ComicSource.fromJson({
  'id': 'paging-source',
  'name': '分页探索源',
  'url': _root,
  'rules': {
    'findUrl':
        entries ?? '连载::/serial?page=searchPage\n完结::/completed?page={{page}}',
    'searchList': '.book',
    'searchName': 'a@text',
    'searchBookUrl': 'a@href',
  },
});

String _books(List<String> ids) => ids
    .map((id) => '<div class="book"><a href="/book/$id">漫画$id</a></div>')
    .join();

Finder get _list => find.descendant(
  of: find.byType(ExploreResults),
  matching: find.byType(ListView),
);
Finder get _scrollable =>
    find.descendant(of: _list, matching: find.byType(Scrollable));

Future<void> _reach(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    240,
    scrollable: _scrollable,
  );
  await tester.pumpAndSettle();
}

class _LinkedRuntime extends SourceRuntime {
  _LinkedRuntime(ComicSource source, this.load)
    : super(source: source, fetcher: FakeFetcher((_) => ''));

  final Paged<Book> Function(int page, String? nextUrl) load;

  @override
  Future<Paged<Book>> explore(
    String entryUrl, {
    int page = 1,
    String? nextUrl,
  }) async => load(page, nextUrl);
}

void main() {
  late AppState state;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri) respond;
  final service = SourceService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source());
    respond = (_) => _books(['1']);
    fetcher = FakeFetcher((uri) => respond(uri));
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });
  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<void> showExplore(
    WidgetTester tester, {
    String category = '连载',
    Brightness brightness = Brightness.light,
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ExploreScreen(state: state),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, category));
    await tester.pumpAndSettle();
  }

  testWidgets('加载更多按页请求、去重追加并保持滚动位置，重复整页会停止', (tester) async {
    final second = Completer<String>();
    respond = (uri) => switch (uri.queryParameters['page']) {
      '1' => _books(['1', '2', '3', '4', '5', '6']),
      '2' => second.future,
      _ => _books(['7', '8']),
    };
    await showExplore(tester);
    await _reach(tester, '加载更多');
    final position = tester.state<ScrollableState>(_scrollable).position;
    final offset = position.pixels;
    await tester.tap(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(fetcher.requests, hasLength(2), reason: '重复点击只发一个第二页请求');
    expect(find.text('加载中…'), findsOneWidget);
    expect(find.text('漫画6'), findsOneWidget);
    second.complete(_books(['5', '6', '7', '8']));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(_scrollable).position, same(position));
    expect(position.pixels, closeTo(offset, 0.1));
    expect(
      tester.widget<ListView>(_list).semanticChildCount,
      9,
      reason: '8 部不同漫画和分页入口',
    );
    await _reach(tester, '加载更多');
    expect(find.text('漫画7'), findsOneWidget);
    expect(find.text('漫画8'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('已经到底了'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(fetcher.requests.map((uri) => uri.queryParameters['page']), [
      '1',
      '2',
      '3',
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('下一页失败保留列表并重试同页，窄屏大字号按钮可操作：${brightness.name}', (tester) async {
      var attempts = 0;
      respond = (uri) {
        final page = uri.queryParameters['page'];
        if (page == '1') return _books(['1']);
        if (page == '2' && attempts++ == 0) throw FetchException('offline');
        return page == '2' ? _books(['2']) : '<html></html>';
      };
      await showExplore(
        tester,
        brightness: brightness,
        size: const Size(320, 480),
        textScale: 2,
      );
      await _reach(tester, '加载更多');
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('漫画1'), findsOneWidget);
      expect(find.text('暂时无法加载更多'), findsOneWidget);
      await _reach(tester, '重试加载');
      await tester.tap(find.text('重试加载'));
      await tester.pumpAndSettle();
      await _reach(tester, '加载更多');
      expect(find.text('漫画2'), findsOneWidget);
      expect(find.text('暂时无法加载更多'), findsNothing);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('已经到底了'), findsOneWidget);
      expect(fetcher.requests.map((uri) => uri.queryParameters['page']), [
        '1',
        '2',
        '2',
        '3',
      ]);
      expect(state.sources.single.failCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('切换分类后旧下一页${fails ? '失败' : '晚到'}不混入新列表', (tester) async {
      final old = Completer<String>();
      respond = (uri) => uri.path == '/completed'
          ? _books(['完结'])
          : uri.queryParameters['page'] == '1'
          ? _books(['连载'])
          : old.future;
      await showExplore(tester);
      await _reach(tester, '加载更多');
      await tester.tap(find.text('加载更多'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, '完结'));
      await tester.pumpAndSettle();
      if (fails) {
        old.completeError(FetchException('old page failed'));
      } else {
        old.complete(_books(['旧页']));
      }
      await tester.pumpAndSettle();
      expect(find.text('漫画完结'), findsOneWidget);
      expect(find.text('漫画旧页'), findsNothing);
      expect(find.text('暂时无法加载更多'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('下拉刷新重置分页，旧的加载更多响应不混入刷新后的首屏', (tester) async {
    var refreshed = false;
    final pending = Completer<String>();
    respond = (uri) => !refreshed && uri.queryParameters['page'] == '2'
        ? pending.future
        : _books(['${refreshed ? '新' : '旧'}${uri.queryParameters['page']}']);
    await showExplore(tester);
    await _reach(tester, '加载更多');
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(find.text('加载中…'), findsOneWidget);
    refreshed = true;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    pending.complete(_books(['旧2']));
    await tester.pumpAndSettle();
    expect(find.text('漫画新1'), findsOneWidget);
    expect(find.text('漫画旧2'), findsNothing);
    await _reach(tester, '加载更多');
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('漫画新2'), findsOneWidget);
    expect(fetcher.requests.map((uri) => uri.queryParameters['page']), [
      '1',
      '2',
      '1',
      '2',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有分页规则的固定分类不显示加载更多入口', (tester) async {
    await state.addSourceManual(_source(entries: '推荐::/featured'));
    await showExplore(tester, category: '推荐');
    expect(find.text('漫画1'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('已经到底了'), findsNothing);
    expect(fetcher.requests, hasLength(1));
  });

  testWidgets('页码算术模板沿用引擎替换，偏移从 0 递增到 20', (tester) async {
    await state.addSourceManual(
      _source(entries: '推荐::/serial?offset={{20*(searchPage-1)}}'),
    );
    respond = (uri) => _books([uri.queryParameters['offset']!]);
    await showExplore(tester, category: '推荐');
    await _reach(tester, '加载更多');
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('漫画0'), findsOneWidget);
    expect(find.text('漫画20'), findsOneWidget);
    expect(fetcher.requests.map((uri) => uri.queryParameters['offset']), [
      '0',
      '20',
    ]);
  });

  testWidgets('源返回下一页链接时优先跟随链接，链接结束后停止', (tester) async {
    await state.addSourceManual(
      _source(entries: '推荐::/featured?page=searchPage'),
    );
    const next = '$_root/more?cursor=a';
    final requests = <(int, String?)>[];
    service.debugRuntimeOverride = (source) =>
        _LinkedRuntime(source, (page, nextUrl) {
          requests.add((page, nextUrl));
          return Paged([
            Book(name: '漫画$page', bookUrl: '$_root/book/$page'),
          ], nextPage: page == 1 ? next : null);
        });
    await showExplore(tester, category: '推荐');
    await _reach(tester, '加载更多');
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('漫画1'), findsOneWidget);
    expect(find.text('漫画2'), findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
    expect(requests, [(1, null), (2, next)]);
    expect(tester.takeException(), isNull);
  });
}
