import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

String _results(String query) =>
    '<div class="item"><a class="title" href="/book/1">结果：$query</a></div>';

Future<void> _showSearch(
  WidgetTester tester,
  AppState state, {
  Duration sourceTimeout = const Duration(days: 1),
}) => tester.pumpWidget(
  MaterialApp(
    home: SearchScreen(state: state, sourceTimeout: sourceTimeout),
  ),
);

void main() {
  late AppState state;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri uri) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(
      ComicSource.fromPpcatFlat({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'https://example.com',
        'ruleSearchUrl': '/search?q=searchKey',
        'ruleSearchList': 'class.item',
        'ruleSearchName': 'class.title@text',
        'ruleSearchBookUrl': 'class.title@href',
      }),
    );
    respond = (uri) => _results(uri.queryParameters['q']!);
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

  testWidgets('空输入显示从本地恢复的最近 10 词，按新到旧排列', (tester) async {
    for (var i = 0; i < 12; i++) {
      await state.recordSearch('漫画$i');
    }
    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    await _showSearch(tester, restarted);

    expect(find.text('最近10词'), findsOneWidget);
    final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
    expect(
      chips.map((chip) => (chip.label as Text).data),
      List.generate(10, (i) => '漫画${11 - i}'),
    );
    expect(fetcher.requests, isEmpty);
  });

  testWidgets('历史词点击只回填、聚焦并将光标置尾，提交后才记录和搜索', (tester) async {
    await state.recordSearch('海贼王');
    await state.recordSearch('火影忍者');
    await _showSearch(tester, state);

    await tester.tap(find.widgetWithText(ActionChip, '海贼王'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '海贼王');
    expect(
      input.controller!.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(input.focusNode!.hasFocus, isTrue);
    expect(find.byType(ActionChip), findsNothing);
    expect(state.searchHistory, ['火影忍者', '海贼王']);
    expect(fetcher.requests, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(fetcher.requests.single.queryParameters['q'], '海贼王');
    expect(state.searchHistory, ['海贼王', '火影忍者']);
    expect(find.text('结果：海贼王'), findsOneWidget);
  });

  testWidgets('输入草稿和提交空白不写历史、不请求源', (tester) async {
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '未提交的草稿');
    await tester.pump();
    expect(state.searchHistory, isEmpty);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('最近10词'), findsNothing);
    expect(find.text('输入关键词开始聚合搜索'), findsOneWidget);
    expect(find.text('清空'), findsNothing);
    expect(state.searchHistory, isEmpty);
    expect(fetcher.requests, isEmpty);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('空历史与输入草稿的搜索引导保持同一位置和宽度：字号 $scale', (tester) async {
      tester.view.physicalSize = const Size(340, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SearchScreen(state: state),
        ),
      );
      final prompt = find.byType(EmptyStateView);
      final title = find.text('输入关键词开始聚合搜索');
      final emptyBounds = tester.getRect(prompt);
      final titleBounds = tester.getRect(title);

      await tester.enterText(find.byType(TextField), '海');
      await tester.pumpAndSettle();
      expect(tester.getRect(prompt), emptyBounds);
      expect(tester.getRect(title), titleBounds);

      await tester.tap(find.byTooltip('清空输入'));
      await tester.pumpAndSettle();
      expect(tester.getRect(prompt), emptyBounds);
      expect(tester.getRect(title), titleBounds);
      expect(fetcher.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('搜索按钮和键盘提交都会保存去空白后的关键词', (tester) async {
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '  海贼王  ');
    await tester.pump();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' 火影忍者 ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(state.searchHistory, ['火影忍者', '海贼王']);
    expect(fetcher.requests.map((uri) => uri.queryParameters['q']), [
      '海贼王',
      '火影忍者',
    ]);

    await tester.tap(find.byTooltip('清空输入'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(find.text('结果：火影忍者'), findsNothing);
  });

  testWidgets('清空全部立即移除 chips，重新进入和重启都不恢复旧词', (tester) async {
    await state.recordSearch('海贼王');
    await _showSearch(tester, state);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('输入关键词开始聚合搜索'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    await _showSearch(tester, restarted);
    expect(find.byType(ActionChip), findsNothing);
    expect(restarted.searchHistory, isEmpty);
  });

  testWidgets('清空后提交新词，旧请求晚到不会覆盖结果或恢复已清历史', (tester) async {
    final oldResponse = Completer<String>();
    respond = (uri) =>
        uri.queryParameters['q'] == '旧词' ? oldResponse.future : _results('新词');
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '旧词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('正在聚合 1 个源'), findsOneWidget);

    await tester.tap(find.byTooltip('清空输入'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '旧词'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '新词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('结果：新词'), findsOneWidget);

    oldResponse.complete(_results('旧词'));
    await tester.pumpAndSettle();
    expect(find.text('结果：新词'), findsOneWidget);
    expect(find.text('结果：旧词'), findsNothing);
    expect(state.searchHistory, ['新词']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('失败搜索仍保存关键词，方便清空输入后重试', (tester) async {
    respond = (_) => throw FetchException('offline');
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清空输入'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '海贼王'), findsOneWidget);
    expect(state.searchHistory, ['海贼王']);
  });

  testWidgets('离开搜索页后请求完成不会使用已销毁的输入框或 setState', (tester) async {
    final response = Completer<String>();
    respond = (_) => response.future;
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    response.complete(_results('海贼王'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(state.searchHistory, ['海贼王']);
  });

  testWidgets('无匹配时提示修改关键词，点按选中输入内容便于替换', (tester) async {
    respond = (_) => '<html></html>';
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关漫画'), findsOneWidget);
    expect(find.text('暂时无法连接漫画源'), findsNothing);

    await tester.tap(find.text('修改关键词'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.focusNode!.hasFocus, isTrue);
    expect(
      input.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(fetcher.requests, hasLength(1));
  });

  testWidgets('搜索按源显示进度，部分源失败仍保留已到达的结果', (tester) async {
    await state.addSourceManual(
      ComicSource.fromPpcatFlat({
        'bookSourceName': '备用源',
        'bookSourceUrl': 'https://second.example.com',
        'ruleSearchUrl': '/search?q=searchKey',
        'ruleSearchList': 'class.item',
        'ruleSearchName': 'class.title@text',
        'ruleSearchBookUrl': 'class.title@href',
      }),
    );
    final first = Completer<String>();
    final second = Completer<String>();
    respond = (uri) => uri.host == 'example.com' ? first.future : second.future;
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('正在聚合 2 个源'), findsOneWidget);
    expect(find.byType(BookListSkeleton), findsOneWidget);
    final coverRect = tester.getRect(
      find
          .byWidgetPredicate(
            (w) => w is SkeletonBox && w.width == 60 && w.height == 80,
          )
          .first,
    );

    first.complete(_results('海贼王'));
    await tester.pumpAndSettle();
    expect(find.text('正在聚合 2 个源 · 1 成功'), findsOneWidget);
    expect(find.text('结果：海贼王'), findsOneWidget);
    expect(find.text('源: 测试源'), findsOneWidget);
    expect(find.byTooltip('来源：测试源'), findsOneWidget);
    expect(tester.getRect(find.byType(BookCover).first), coverRect);

    second.completeError(FetchException('offline'));
    await tester.pumpAndSettle();
    expect(find.text('结果：海贼王'), findsOneWidget);
    expect(find.text('已聚合 2 个源 · 1 成功 1 失败'), findsOneWidget);
    expect(find.text('1 个源失败：备用源'), findsOneWidget);
    expect(find.text('暂时无法连接漫画源'), findsNothing);
  });

  testWidgets('全部源失败与无匹配分开显示，同名源分别计数且可重试恢复', (tester) async {
    await state.addSourceManual(
      ComicSource.fromPpcatFlat({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'https://second.example.com',
        'ruleSearchUrl': '/search?q=searchKey',
        'ruleSearchList': 'class.item',
        'ruleSearchName': 'class.title@text',
        'ruleSearchBookUrl': 'class.title@href',
      }),
    );
    respond = (_) => throw FetchException('offline');
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('暂时无法连接漫画源'), findsOneWidget);
    expect(find.text('没有找到相关漫画'), findsNothing);
    expect(find.text('已聚合 2 个源 · 2 失败'), findsOneWidget);
    expect(find.text('2 个源失败：测试源、测试源'), findsOneWidget);

    respond = (_) => _results('海贼王');
    await tester.tap(find.text('重新搜索'));
    await tester.pumpAndSettle();
    expect(find.text('结果：海贼王'), findsOneWidget);
    expect(find.text('暂时无法连接漫画源'), findsNothing);
    expect(find.text('已聚合 2 个源 · 2 成功'), findsOneWidget);
    expect(find.text('源: 测试源'), findsOneWidget);
    expect(state.searchHistory, ['海贼王']);
    expect(fetcher.requests, hasLength(4));
  });

  testWidgets('无启用搜索源时提供管理入口，不误报无匹配', (tester) async {
    await state.toggleSource(state.sources.single.id);
    await _showSearch(tester, state);
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('暂无可搜索的源'), findsOneWidget);
    expect(find.text('没有找到相关漫画'), findsNothing);
    expect(fetcher.requests, isEmpty);

    await tester.tap(find.text('管理源'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
  });

  testWidgets('源超时计入聚合状态并点名超时源', (tester) async {
    final hang = Completer<String>();
    respond = (_) => hang.future;
    await _showSearch(
      tester,
      state,
      sourceTimeout: const Duration(milliseconds: 20),
    );
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('已聚合 1 个源 · 1 超时'), findsOneWidget);
    expect(find.text('1 个源超时：测试源'), findsOneWidget);
    expect(find.text('暂时无法连接漫画源'), findsOneWidget);
    expect(find.text('没有找到相关漫画'), findsNothing);

    hang.complete(_results('海贼王'));
    await tester.pumpAndSettle();
    expect(find.text('结果：海贼王'), findsNothing);
    expect(find.text('已聚合 1 个源 · 1 超时'), findsOneWidget);
  });

  testWidgets('搜索页展示大标题，空历史与设计稿间距一致', (tester) async {
    await _showSearch(tester, state);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('最近10词'), findsNothing);
    expect(find.text('输入关键词开始聚合搜索'), findsOneWidget);
    final title = tester.getRect(find.text('搜索').first);
    final field = tester.getRect(find.byType(TextField));
    expect(title.left, closeTo(20, 0.5));
    expect(field.left, closeTo(20, 0.5));
    expect(field.top, greaterThan(title.bottom));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('窄屏键盘展开时可滚动到长历史词并完整回填：字号 $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const query = '很长的漫画名称包含特别篇和番外篇以及完整的搜索关键词';
      await state.recordSearch(query);
      for (var i = 0; i < 9; i++) {
        await state.recordSearch('其他漫画的完整名称 $i');
      }
      await _showSearch(tester, state);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final chip = find.widgetWithText(ActionChip, query);
      await tester.scrollUntilVisible(
        chip,
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(chip);
      expect(bounds.left, greaterThanOrEqualTo(20));
      expect(bounds.right, lessThanOrEqualTo(300));
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(chip.hitTestable(), findsOneWidget);
      expect(find.byTooltip(query), findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, query);
      expect(input.focusNode!.hasFocus, isTrue);
      expect(state.searchHistory.last, query);
      expect(fetcher.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
