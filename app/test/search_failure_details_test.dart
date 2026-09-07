import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_failure_panel.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(int i, {String? name}) => ComicSource.fromJson({
  'id': '$i',
  'name': name ?? '社区漫画源 $i · 提供完整连载和完结漫画的备用线路',
  'url': 'https://source-$i.example.com',
  'rules': {
    'searchUrl': '/search?q=searchKey',
    'searchList': '.book',
    'searchName': 'a@text',
    'searchBookUrl': 'a@href',
  },
});

void main() {
  late AppState state;
  late FutureOr<String> Function(Uri) respond;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    final fetcher = FakeFetcher((uri) => respond(uri));
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  Future<void> search(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: SearchScreen(state: state),
      ),
    );
    await tester.enterText(find.byType(TextField), '漫画');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  testWidgets('少量失败源面板按内容收拢，列表后可直接管理源', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.addSourceManual(_source(1, name: '社区源 A'));
    await state.addSourceManual(_source(2, name: '社区源 B'));
    respond = (_) => throw FetchException('offline');

    await search(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看失败源'));
    await tester.pumpAndSettle();

    expect(find.text('社区源 A').hitTestable(), findsOneWidget);
    expect(find.text('社区源 B').hitTestable(), findsOneWidget);
    final panel = tester.getRect(find.byType(SearchFailurePanel));
    final list = tester.getRect(
      find.byKey(const ValueKey('search-failure-list')),
    );
    final action = tester.getRect(find.widgetWithText(FilledButton, '管理源'));
    expect(panel.height, lessThan(320));
    expect(action.top - list.bottom, inInclusiveRange(8, 16));
    expect(action.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('管理源'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
  });

  for (final textScale in [1.0, 1.6]) {
    testWidgets('窄屏 $textScale 倍字号下，大量失败源不挤掉结果且可查看完整列表', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (var i = 0; i < 37; i++) {
        await state.addSourceManual(_source(i));
      }
      respond = (uri) {
        if (uri.host == 'source-0.example.com') {
          return '<div class="book"><a href="/book">仍可阅读的漫画</a></div>';
        }
        throw FetchException('offline');
      };
      await search(tester, textScale: textScale);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('仍可阅读的漫画').hitTestable(), findsOneWidget);
      expect(tester.getSize(find.byType(BookTile)).height, greaterThan(80));

      await tester.tap(find.byTooltip('查看失败源'));
      await tester.pumpAndSettle();
      expect(find.text('未响应的源 · 36'), findsOneWidget);
      final last = find.text(_source(36).name);
      await tester.scrollUntilVisible(
        last,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('search-failure-list')),
          matching: find.byType(Scrollable),
        ),
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(find.text('连接失败'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('管理源'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceScreen), findsOneWidget);
      expect(find.text('未响应的源 · 36'), findsNothing);
    });
  }

  testWidgets('展开详情后新到的超时继续加入，更新源后清除过时失败', (tester) async {
    await state.addSourceManual(_source(1));
    await state.addSourceManual(_source(2));
    final second = Completer<String>();
    respond = (uri) {
      if (uri.host == 'source-2.example.com') return second.future;
      throw FetchException('offline');
    };
    await search(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看失败源'));
    await tester.pumpAndSettle();
    expect(find.text('未响应的源 · 1'), findsOneWidget);
    expect(find.text('连接失败'), findsOneWidget);

    second.completeError(TimeoutException('timeout'));
    await tester.pumpAndSettle();
    expect(find.text('未响应的源 · 2'), findsOneWidget);
    expect(find.text(_source(2).name), findsOneWidget);
    expect(find.text('连接超时'), findsOneWidget);

    await state.addSourceManual(_source(1));
    await tester.pumpAndSettle();
    expect(find.text('暂无失败源'), findsOneWidget);
    expect(find.text('连接失败'), findsNothing);
    expect(find.text('连接超时'), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('漫画源已更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
