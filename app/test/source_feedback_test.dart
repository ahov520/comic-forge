import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/source_update.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

final _longReason =
    '${List.filled(60, '多个仓库连接失败，请检查来源地址和网络。').join('\n')}\n最后一条详情';

class _FailingRepoClient extends RepoClient {
  _FailingRepoClient() : super(fetcher: FakeFetcher((_) => ''));

  @override
  Future<StoreBundle> subscribe(String input) async =>
      throw FetchException(_longReason);
}

class _PendingRepoClient extends RepoClient {
  _PendingRepoClient(this.result) : super(fetcher: FakeFetcher((_) => ''));

  final Future<StoreBundle> result;

  @override
  Future<StoreBundle> subscribe(String input) => result;
}

class _PendingRefreshState extends AppState {
  late Future<RepoRefreshResult> refreshResult;

  @override
  Future<RepoRefreshResult> refreshRepo(String repoUrl, {RepoClient? client}) =>
      refreshResult;
}

void main() {
  late _PendingRefreshState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = _PendingRefreshState();
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'existing',
        'name': '现有漫画源',
        'url': 'https://existing.example',
        'rules': {'searchUrl': '/search', 'searchList': '.item'},
      }),
    );
  });
  tearDown(() => state.dispose());

  testWidgets('订阅等待期间保留页头按钮的宽度与位置', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<StoreBundle>();
    await tester.pumpWidget(
      MaterialApp(
        home: SourceScreen(
          state: state,
          repoClient: _PendingRepoClient(pending.future),
        ),
      ),
    );
    final subscribe = find.widgetWithText(TextButton, '＋ 订阅仓库');
    final initialBounds = tester.getRect(subscribe);
    await tester.tap(subscribe);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'github.com/team/comics');
    await tester.tap(find.widgetWithText(FilledButton, '订阅'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(subscribe), initialBounds);
    expect(tester.widget<TextButton>(subscribe).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.completeError(FetchException('offline'));
    await tester.pumpAndSettle();
    expect(tester.getRect(subscribe), initialBounds);
    expect(tester.widget<TextButton>(subscribe).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('订阅失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仓库刷新进度占位稳定，长仓库名不会随加载伸缩', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final refresh = Completer<RepoRefreshResult>();
    state.refreshResult = refresh.future;
    const repo = 'https://github.com/example/very-long-comic-source-repository';
    await state.addRepoSubscribed(repo, const []);
    await tester.pumpWidget(MaterialApp(home: SourceScreen(state: state)));
    final name = find.text(repoDisplayName(repo));
    final initialNameSize = tester.getSize(name);
    final initialCardSize = tester.getSize(find.byType(Card));
    final action = tester.getRect(find.byTooltip('检查更新'));

    await tester.tap(find.byTooltip('检查更新'));
    await tester.pump();
    expect(tester.getSize(name), initialNameSize);
    expect(tester.getSize(find.byType(Card)), initialCardSize);
    expect(
      tester.getCenter(find.byType(CircularProgressIndicator)),
      action.center,
    );
    refresh.complete(
      RepoRefreshResult(repo: repo, added: 0, updated: 0, total: 1),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(name), initialNameSize);
    expect(tester.getSize(find.byType(Card)), initialCardSize);
    expect(find.byTooltip('检查更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('长操作反馈不挤走源列表，全文可滚动查看并关闭：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: SourceScreen(state: state, repoClient: _FailingRepoClient()),
        ),
      );
      await tester.tap(find.text('＋ 订阅仓库'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'github.com/team/comics');
      await tester.tap(find.widgetWithText(FilledButton, '订阅'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('现有漫画源').hitTestable(), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(state.sources.single.enabled, isFalse);
      await tester.tap(find.byTooltip('查看操作详情'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains(_longReason),
      );
      final scrollable = find
          .ancestor(
            of: find.byType(SelectableText),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(500));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.extentAfter, 0);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.textContaining('订阅失败'), findsNothing);
      expect(find.text('现有漫画源').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('操作详情打开时，源体检进度会更新为最终结果', (tester) async {
    final pending = Completer<String>();
    final service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher((_) => pending.future),
    );
    addTearDown(() {
      service.debugRuntimeOverride = null;
      service.debugClearSwitchCache();
    });
    await tester.pumpWidget(MaterialApp(home: SourceScreen(state: state)));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('源健康体检'));
    await tester.tap(find.text('源健康体检'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看操作详情'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('体检中'),
    );
    pending.complete('<html></html>');
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('体检完成：可用 1 / 1'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
