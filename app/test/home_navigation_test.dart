import 'dart:async';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('窄屏大字号切换标签保留搜索结果与草稿，离开后收起键盘：dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final state = AppState()..darkMode = dark;
      addTearDown(state.dispose);
      final source = ComicSource.fromJson({
        'id': 'home-search',
        'name': '测试源',
        'url': 'https://home.example',
        'rules': {
          'searchUrl': '/search?q={{key}}',
          'searchList': '.book',
          'searchName': '.title@text',
          'searchBookUrl': '.title@href',
        },
      });
      await state.addSourceManual(source);
      final response = Completer<String>();
      final fetcher = FakeFetcher((_) => response.future);
      final service = SourceService.instance;
      service.debugClearSwitchCache();
      service.debugRuntimeOverride = (source) =>
          SourceRuntime(source: source, fetcher: fetcher);
      addTearDown(() {
        service.debugRuntimeOverride = null;
        service.debugClearSwitchCache();
      });
      await tester.pumpWidget(ComicForgeApp(state: state));
      await tester.pumpAndSettle();
      expect(
        find.byType(ExploreScreen, skipOffstage: false),
        findsNothing,
        reason: '未访问的探索页不应提前加载',
      );

      Future<void> select(String label) async {
        await tester.tap(find.widgetWithText(NavigationDestination, label));
        await tester.pumpAndSettle();
      }

      await select('搜索');
      await tester.enterText(find.byType(TextField), '海贼王');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await select('设置');
      response.complete(
        '<div class="book"><a class="title" href="/book">海贼王（测试命中）</a></div>',
      );
      await tester.pumpAndSettle();
      await select('搜索');
      expect(find.widgetWithText(BookTile, '海贼王（测试命中）'), findsOneWidget);
      expect(fetcher.requests, hasLength(1));

      await tester.enterText(find.byType(TextField), '尚未提交的搜索词');
      expect(tester.testTextInput.isVisible, isTrue);
      await select('源');
      expect(tester.testTextInput.isVisible, isFalse);
      await select('书架');
      await select('探索');
      await select('搜索');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '尚未提交的搜索词',
      );
      expect(fetcher.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
