import 'dart:async';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

StoreBundle _bundle(String input) => StoreBundle(
  ref: RepoRef.parse(input)!,
  meta: StoreMeta(),
  sources: [
    ComicSource.fromJson({
      'id': 'subscribed-source',
      'name': '漫画源',
      'url': 'https://comic.example',
    }),
  ],
  track: 'A',
);

class _ControlledRepoClient extends RepoClient {
  _ControlledRepoClient() : super(fetcher: FakeFetcher((_) => ''));

  final requests = <String>[];
  Future<StoreBundle> Function(String)? respond;

  @override
  Future<StoreBundle> subscribe(String input) async {
    requests.add(input);
    return respond == null ? _bundle(input) : await respond!(input);
  }
}

void main() {
  late AppState state;
  late _ControlledRepoClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    client = _ControlledRepoClient();
  });
  tearDown(() => state.dispose());

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SourceScreen(state: state, repoClient: client),
                ),
              ),
              child: const Text('打开源管理'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开源管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 订阅仓库'));
    await tester.pumpAndSettle();
  }

  testWidgets('无效仓库地址保留在弹窗中并提示，改正后才发起订阅', (tester) async {
    await openDialog(tester);
    for (final input in [
      '',
      'github.com/team',
      'ftp://example.com/store.json',
    ]) {
      await tester.enterText(find.byType(TextField), input);
      await tester.tap(find.widgetWithText(FilledButton, '订阅'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(input.isEmpty ? '请输入仓库地址' : '请输入仓库地址或 http(s) 源列表 URL'),
        findsOneWidget,
      );
      expect(client.requests, isEmpty);
    }
    await tester.enterText(find.byType(TextField), 'gitee.com/team/comics');
    await tester.pumpAndSettle();
    expect(find.text('请输入仓库地址或 http(s) 源列表 URL'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '订阅'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(client.requests, ['gitee.com/team/comics']);
    expect(state.sources.single.id, 'subscribed-source');
    expect(state.repos, ['gitee.com/team/comics']);
    expect(find.textContaining('订阅成功'), findsOneWidget);
    expect(find.textContaining('Track'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('远程源列表 URL 可订阅并写入规范化地址', (tester) async {
    await openDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      '  HTTPS://CDN.EXAMPLE.COM/store.json#frag  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '订阅'));
    await tester.pumpAndSettle();
    expect(client.requests, ['HTTPS://CDN.EXAMPLE.COM/store.json#frag']);
    expect(state.repos, ['https://cdn.example.com/store.json']);
    expect(state.sources.single.id, 'subscribed-source');
    expect(state.repoLastRefresh[state.repos.single], greaterThan(0));
    expect(find.textContaining('订阅成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('输入仓库地址后可直接用键盘订阅，取消不会发请求', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'team/comics');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(client.requests, isEmpty);
    await tester.tap(find.text('＋ 订阅仓库'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '  github.com/team/comics  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(client.requests, ['github.com/team/comics']);
    expect(state.sources.single.id, 'subscribed-source');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏大字号键盘展开时仍能看到输入内容并订阅', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openDialog(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byType(EditableText)).bottom,
      lessThanOrEqualTo(160),
    );
    await tester.enterText(find.byType(TextField), 'team/comics');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(state.repos, ['github.com/team/comics']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('源标签页弹出和关闭键盘期间，订阅弹窗与背景均不溢出', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.tap(find.widgetWithText(NavigationDestination, '源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 订阅仓库'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text('＋ 订阅仓库').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final fails in [false, true]) {
    testWidgets('离开源页后订阅${fails ? '失败' : '完成'}，不会更新已销毁的界面', (tester) async {
      final pending = Completer<StoreBundle>();
      client.respond = (_) => pending.future;
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'github.com/team/comics');
      await tester.tap(find.widgetWithText(FilledButton, '订阅'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.requests, ['github.com/team/comics']);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      if (fails) {
        pending.completeError(FetchException('offline'));
      } else {
        pending.complete(_bundle('github.com/team/comics'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(SourceScreen), findsNothing);
      expect(state.repos, fails ? isEmpty : ['github.com/team/comics']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
