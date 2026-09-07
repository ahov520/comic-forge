import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source({
  String name = '探索源',
  String url = 'https://example.com',
  String entries = '连载::/serial\n完结::/completed',
}) => ComicSource.fromPpcatFlat({
  'bookSourceName': name,
  'bookSourceUrl': url,
  'exploreUrl': entries,
  'ruleSearchUrl': '/search?q=searchKey',
  'ruleSearchList': 'class.item',
  'ruleSearchName': 'class.title@text',
  'ruleSearchBookUrl': 'class.title@href',
});

String _books(String name) =>
    '<div class="item"><a class="title" href="/book/1">$name</a></div>';

Future<void> _showExplore(WidgetTester tester, AppState state) =>
    tester.pumpWidget(MaterialApp(home: ExploreScreen(state: state)));

Finder _category(String name) => find.widgetWithText(ChoiceChip, name);

void _expectSourceMenuAligned(WidgetTester tester, Rect field, String name) {
  final item = find
      .ancestor(of: find.text(name).last, matching: find.byType(InkWell))
      .first;
  final rect = tester.getRect(item);
  expect(rect.left, closeTo(field.left, 0.5));
  expect(rect.right, closeTo(field.right, 0.5));
  expect(rect.height, greaterThanOrEqualTo(48));
}

void main() {
  late AppState state;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri uri) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source());
    respond = (_) => _books('发现的漫画');
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

  testWidgets('列表骨架对齐结果封面，切换分类立即移除旧内容并显示加载状态', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final serial = Completer<String>();
    final completed = Completer<String>();
    respond = (uri) => uri.path == '/serial' ? serial.future : completed.future;
    await _showExplore(tester, state);
    expect(find.text('选一个分类开始探索'), findsOneWidget);
    expect(fetcher.requests, isEmpty);
    expect(
      tester.getTopLeft(_category('连载')).dx,
      tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dx,
      reason: '分类不足一行时仍与源入口左对齐',
    );
    final selector = tester.getRect(
      find.byType(DropdownButtonFormField<String>),
    );
    final serialChip = tester.getRect(_category('连载'));
    expect(selector.height, 36);
    expect(serialChip.top - selector.bottom, 12);
    expect(tester.getRect(_category('完结')).left - serialChip.right, 8);

    await tester.tap(_category('连载'));
    await tester.pump();
    expect(find.byType(BookListSkeleton), findsOneWidget);
    expect(find.byType(BookTile), findsNothing);
    final coverPlaceholder = find.byWidgetPredicate(
      (widget) =>
          widget is SkeletonBox && widget.width == 60 && widget.height == 80,
    );
    final coverRect = tester.getRect(coverPlaceholder.first);
    final loadingCard = tester.getRect(
      find
          .descendant(
            of: find.byType(BookListSkeleton),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(loadingCard.top - tester.getRect(_category('连载')).bottom, 12);

    serial.complete(_books('连载漫画'));
    await tester.pumpAndSettle();
    expect(find.byType(BookListSkeleton), findsNothing);
    expect(find.text('连载漫画'), findsOneWidget);
    expect(tester.getRect(find.byType(BookCover).first), coverRect);

    await tester.tap(_category('完结'));
    await tester.pump();
    expect(find.byType(BookListSkeleton), findsOneWidget);
    expect(find.text('连载漫画'), findsNothing);
    completed.complete(_books('完结漫画'));
    await tester.pumpAndSettle();
    expect(find.text('完结漫画'), findsOneWidget);
    expect(find.text('连载漫画'), findsNothing);
    expect(fetcher.requests.map((uri) => uri.path), ['/serial', '/completed']);
  });

  testWidgets('快速切换分类后，旧请求晚到不会覆盖当前分类', (tester) async {
    final old = Completer<String>();
    respond = (uri) => uri.path == '/serial' ? old.future : _books('当前分类漫画');
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pump();
    await tester.tap(_category('完结'));
    await tester.pumpAndSettle();
    expect(find.text('当前分类漫画'), findsOneWidget);

    old.complete(_books('旧分类漫画'));
    await tester.pumpAndSettle();
    expect(find.text('当前分类漫画'), findsOneWidget);
    expect(find.text('旧分类漫画'), findsNothing);
    expect(tester.widget<ChoiceChip>(_category('完结')).selected, isTrue);
  });

  testWidgets('失败、空分类与结果分别展示，重试可恢复并回报源健康', (tester) async {
    respond = (_) => throw FetchException('offline');
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载漫画'), findsOneWidget);
    expect(find.text('这个分类还没有漫画'), findsNothing);
    expect(state.sources.single.failCount, 1);

    respond = (_) => '<html></html>';
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有漫画'), findsOneWidget);
    expect(find.text('暂时无法加载漫画'), findsNothing);
    expect(state.sources.single.failCount, 0);

    respond = (_) => _books('恢复后的漫画');
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('恢复后的漫画'), findsOneWidget);
    expect(find.text('这个分类还没有漫画'), findsNothing);
    expect(fetcher.requests, hasLength(3));
  });

  testWidgets('无源时可进入管理，添加源返回后即可选择分类', (tester) async {
    final source = state.sources.single;
    await state.removeSource(source.id);
    await _showExplore(tester, state);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('暂无可用漫画源'), findsOneWidget);
    await tester.tap(find.text('管理源'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);

    await state.addSourceManual(source);
    Navigator.of(tester.element(find.byType(SourceScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('选一个分类开始探索'), findsOneWidget);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    expect(find.text('发现的漫画'), findsOneWidget);
    expect(fetcher.requests.single.host, 'example.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets('源入口只列出启用源，切换后清空旧结果并展示新源分类', (tester) async {
    await state.addSourceManual(
      _source(
        name: '备用源',
        url: 'https://second.example.com',
        entries: '最新::/latest',
      ),
    );
    final disabled = _source(name: '已停用源', url: 'https://disabled.example.com');
    await state.addSourceManual(disabled);
    await state.toggleSource(disabled.id);
    respond = (uri) => _books(uri.host == 'example.com' ? '原来的漫画' : '最新漫画');
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    expect(find.text('原来的漫画'), findsOneWidget);

    final selector = tester.getRect(
      find.byType(DropdownButtonFormField<String>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('已停用源'), findsNothing);
    _expectSourceMenuAligned(tester, selector, '备用源');
    await tester.tap(find.text('备用源').last);
    await tester.pumpAndSettle();
    expect(find.text('原来的漫画'), findsNothing);
    expect(_category('连载'), findsNothing);
    expect(find.text('选一个分类开始探索'), findsOneWidget);
    expect(fetcher.requests, hasLength(1));

    await tester.tap(_category('最新'));
    await tester.pumpAndSettle();
    expect(find.text('最新漫画'), findsOneWidget);
    expect(
      fetcher.requests.last.toString(),
      'https://second.example.com/latest',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('不提供探索分类的源提示切换或进入搜索', (tester) async {
    await state.addSourceManual(_source(entries: ''));
    await _showExplore(tester, state);
    expect(find.text('当前源暂无探索分类'), findsOneWidget);
    expect(find.text('选一个分类开始探索'), findsNothing);
    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(fetcher.requests, isEmpty);
  });

  testWidgets('当前源加载中被禁用会切到可用源，旧响应和移除源不会残留结果', (tester) async {
    final firstSource = state.sources.single;
    final secondSource = _source(
      name: '备用探索源',
      url: 'https://second.example.com',
    );
    await state.addSourceManual(secondSource);
    final old = Completer<String>();
    respond = (uri) => uri.host == 'example.com' ? old.future : _books('备用源漫画');
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pump();

    await state.toggleSource(firstSource.id);
    await tester.pumpAndSettle();
    expect(find.text('选一个分类开始探索'), findsOneWidget);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    expect(find.text('备用源漫画'), findsOneWidget);

    old.complete(_books('禁用源漫画'));
    await tester.pumpAndSettle();
    expect(find.text('备用源漫画'), findsOneWidget);
    expect(find.text('禁用源漫画'), findsNothing);
    await state.removeSource(secondSource.id);
    await tester.pumpAndSettle();
    expect(find.text('暂无可用漫画源'), findsOneWidget);
    expect(find.byType(BookTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字号长源名与末尾分类可切换，空态按钮可操作：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const name = '很长的社区漫画源名称与站点说明';
      const category = '包含特别篇和番外篇的长分类名称';
      await state.addSourceManual(
        _source(
          name: name,
          url: 'https://second.example.com',
          entries: '$category::/serial\n最新::/latest',
        ),
      );
      respond = (_) => '<html></html>';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF169876),
              brightness: brightness,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ExploreScreen(state: state),
        ),
      );
      final selector = tester.getRect(
        find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      _expectSourceMenuAligned(tester, selector, name);
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      await tester.tap(_category(category));
      await tester.pumpAndSettle();
      expect(find.text('这个分类还没有漫画'), findsOneWidget);
      await tester.ensureVisible(find.text('重新加载'));
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(fetcher.requests, hasLength(2));
      expect(
        fetcher.requests.every((uri) => uri.host == 'second.example.com'),
        isTrue,
      );
      await tester.drag(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_category('最新')).right,
        closeTo(selector.right, 0.5),
      );
      await tester.tap(_category('最新'));
      await tester.pumpAndSettle();
      expect(fetcher.requests, hasLength(3));
      expect(fetcher.requests.last.path, '/latest');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('页头是大标题而非 AppBar，结果可下拉刷新', (tester) async {
    var loads = 0;
    respond = (_) {
      loads++;
      return _books('发现的漫画$loads');
    };
    await _showExplore(tester, state);
    expect(find.text('探索'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);

    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    expect(find.text('发现的漫画1'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.fling(find.text('发现的漫画1'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(find.text('发现的漫画2'), findsOneWidget);
    expect(find.text('发现的漫画1'), findsNothing);
    expect(loads, 2);
  });

  testWidgets('离开探索页后请求完成不会更新已销毁的页面', (tester) async {
    final response = Completer<String>();
    respond = (_) => response.future;
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.complete(_books('漫画'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新失败保留漫画列表并提示重试，重试恢复后更新内容和源健康', (tester) async {
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    respond = (_) => throw FetchException('offline');
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('发现的漫画'), findsOneWidget);
    expect(find.text('刷新失败，已保留原列表'), findsOneWidget);
    expect(find.text('暂时无法加载漫画'), findsNothing);
    expect(state.sources.single.failCount, 1);
    expect(tester.takeException(), isNull);

    respond = (_) => _books('重试后的漫画');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('重试后的漫画'), findsOneWidget);
    expect(find.text('发现的漫画'), findsNothing);
    expect(state.sources.single.failCount, 0);
    expect(fetcher.requests, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新中保留当前结果，成功后的首帧直接显示新列表而不闪骨架', (tester) async {
    await _showExplore(tester, state);
    await tester.tap(_category('连载'));
    await tester.pumpAndSettle();
    final pending = Completer<String>();
    respond = (_) => pending.future;
    final refreshed = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(find.text('发现的漫画'), findsOneWidget);
    expect(find.byType(BookListSkeleton), findsNothing);
    pending.complete(_books('刷新后的漫画'));
    await refreshed;
    await tester.pump();
    expect(find.text('刷新后的漫画'), findsOneWidget);
    expect(find.byType(BookListSkeleton), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('同一分类重新加载后，旧刷新${fails ? '失败' : '晚到'}不能覆盖当前结果', (tester) async {
      await _showExplore(tester, state);
      await tester.tap(_category('连载'));
      await tester.pumpAndSettle();
      final pending = Completer<String>();
      respond = (_) => pending.future;
      final refreshed = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      respond = (_) => _books('重新加载的漫画');
      await tester.tap(_category('连载'));
      await tester.pumpAndSettle();
      expect(find.text('重新加载的漫画'), findsOneWidget);

      if (fails) {
        pending.completeError(FetchException('old refresh failed'));
      } else {
        pending.complete(_books('旧刷新的漫画'));
      }
      await refreshed;
      await tester.pumpAndSettle();
      expect(find.text('重新加载的漫画'), findsOneWidget);
      expect(find.text('旧刷新的漫画'), findsNothing);
      expect(find.text('刷新失败，已保留原列表'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
