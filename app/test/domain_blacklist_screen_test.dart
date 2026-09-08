import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/domain_blacklist_screen.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SourceService.instance.debugResetNetworkPolicy();
    state = AppState();
  });

  tearDown(() {
    state.dispose();
    SourceService.instance.debugResetNetworkPolicy();
  });

  Future<void> showScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DomainBlacklistScreen(state: state)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置页展示数量并进入名单，可新增、拒绝非法项、删除', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('域名黑名单'), 120);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('域名黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('未拦截任何域名'), findsOneWidget);
    await tester.tap(find.text('域名黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('尚未拦截任何域名'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('domain-block-input')),
      'not a host',
    );
    await tester.tap(find.byKey(const ValueKey('domain-block-add')));
    await tester.pumpAndSettle();
    expect(find.text('请输入域名或网址，例如 evil.com'), findsOneWidget);
    expect(state.blockedDomains, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('domain-block-input')),
      'https://ADS.example/path',
    );
    await tester.tap(find.byKey(const ValueKey('domain-block-add')));
    await tester.pumpAndSettle();
    expect(find.text('ads.example'), findsOneWidget);
    expect(find.text('已拦截 ads.example'), findsOneWidget);
    expect(state.blockedDomains, ['ads.example']);

    await tester.enterText(
      find.byKey(const ValueKey('domain-block-input')),
      'ads.example',
    );
    await tester.tap(find.byKey(const ValueKey('domain-block-add')));
    await tester.pumpAndSettle();
    expect(find.text('ads.example 已在名单中'), findsOneWidget);

    await tester.tap(find.byTooltip('移除 ads.example'));
    await tester.pumpAndSettle();
    expect(state.blockedDomains, isEmpty);
    expect(find.text('尚未拦截任何域名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外部更新名单后界面刷新', (tester) async {
    await showScreen(tester);
    await state.addBlockedDomain('tracker.example');
    await tester.pumpAndSettle();
    expect(find.text('tracker.example'), findsOneWidget);
    expect(find.text('已拦截 1 个域名'), findsOneWidget);
  });
}
