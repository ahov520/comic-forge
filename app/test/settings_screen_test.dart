import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _showSettings(
  WidgetTester tester,
  AppState state, {
  Brightness brightness = Brightness.light,
}) async {
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
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: SettingsScreen(state: state)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });
  tearDown(() {
    state.dispose();
    SourceService.instance.adBlock = null;
  });

  for (final brightness in Brightness.values) {
    testWidgets('设置状态随外部更新刷新，窄屏大字号仍可清除规则：${brightness.name}', (tester) async {
      await _showSettings(tester, state, brightness: brightness);
      expect(find.text('未配置服务器'), findsOneWidget);
      await state.setWebDavConfig({
        'url': 'https://backup.example/dav/comic-forge',
      });
      await state.setAdBlock('{"urlRules":["tracking","advert"]}');
      await tester.pumpAndSettle();
      expect(find.text('backup.example'), findsOneWidget);
      expect(find.text('已启用 · 2 条图片规则'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('清除规则'));
      await tester.tap(find.byTooltip('清除规则'));
      await tester.pumpAndSettle();
      expect(state.adBlock, isNull);
      expect(find.byTooltip('导入广告规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('WebDAV 大字号面板在键盘展开后仍可滚动到备份与恢复按钮', (tester) async {
    await _showSettings(tester, state);
    await tester.tap(find.text('WebDAV 备份 / 恢复'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('备份'));
    expect(find.text('备份').hitTestable(), findsOneWidget);
    expect(find.text('恢复').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('备份')).bottom, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
