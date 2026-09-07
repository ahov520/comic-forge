import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(String version) => ComicSource.fromJson({
  'id': 'editable-health-source',
  'name': '源$version',
  'url': 'https://$version.example.com',
  'rules': {
    'searchUrl': '/search?q=searchKey',
    'searchList': '.book',
    'searchName': 'a@text',
    'searchBookUrl': 'a@href',
    'findUrl': '推荐::/featured',
  },
});

const _page = '<div class="book"><a href="/book">漫画</a></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late ComicSource updated;
  late Completer<void> started;
  late Completer<String> response;
  late SourceService service;

  setUp(() async {
    service = SourceService.instance;
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source('old'));
    updated = _source('new')
      ..failCount = 2
      ..lastError = '新定义的错误记录'
      ..lastFailedAt = 200
      ..lastOkAt = 100;
    final fetcher = FakeFetcher((_) {
      if (!started.isCompleted) started.complete();
      return response.future;
    });
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  void finish(bool fails) {
    if (fails) {
      response.completeError(FetchException('旧定义的失败'));
    } else {
      response.complete(_page);
    }
  }

  Future<void> expectCurrentHealth() async {
    expect(updated.failCount, 2);
    expect(updated.lastError, '新定义的错误记录');
    expect(updated.lastFailedAt, 200);
    expect(updated.lastOkAt, 100);
    expect(updated.isUnhealthy, isFalse);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.sources.single.failCount, 2);
    expect(restored.sources.single.lastError, '新定义的错误记录');
  }

  for (final automatic in [false, true]) {
    for (final fails in [false, true]) {
      test(
        '${automatic ? '自动' : '手动'}体检期间编辑源，旧${fails ? '失败' : '成功'}不改写新定义的健康',
        () async {
          started = Completer<void>();
          response = Completer<String>();
          final pending = automatic
              ? state.autoProbeIfNeeded()
              : state.probeSources().then<void>((_) {});
          await started.future;
          await state.addSourceManual(updated);
          finish(fails);
          await pending;
          await expectCurrentHealth();
        },
      );
    }
  }

  for (final search in [false, true]) {
    for (final fails in [false, true]) {
      testWidgets(
        '${search ? '搜索' : '探索'}期间编辑源，旧${fails ? '失败' : '成功'}不改写新定义的健康',
        (tester) async {
          started = Completer<void>();
          response = Completer<String>();
          await tester.pumpWidget(
            MaterialApp(
              home: search
                  ? SearchScreen(state: state)
                  : ExploreScreen(state: state),
            ),
          );
          if (search) {
            await tester.enterText(find.byType(TextField), '漫画');
            await tester.testTextInput.receiveAction(TextInputAction.search);
          } else {
            await tester.tap(find.widgetWithText(ChoiceChip, '推荐'));
          }
          await tester.pump();
          expect(started.isCompleted, isTrue);
          await state.addSourceManual(updated);
          finish(fails);
          await tester.pumpAndSettle();
          await expectCurrentHealth();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
