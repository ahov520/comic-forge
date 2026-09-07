import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _showSettings(
  WidgetTester tester,
  AppState state, {
  Brightness brightness = Brightness.light,
  Size size = const Size(320, 640),
  double textScale = 2,
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

  testWidgets('设置行保留 14px 标题，操作图标与箭头对齐且整块区域可点击', (tester) async {
    await _showSettings(
      tester,
      state,
      size: const Size(340, 720),
      textScale: 1,
    );
    final firstTitle = tester.getRect(find.text('深色模式'));
    for (final label in [
      '深色模式',
      'WebDAV 备份 / 恢复',
      '广告拦截规则',
      'Comic Forge v0.1.0',
    ]) {
      final title = find.text(label);
      final tile = find.widgetWithText(ListTile, label);
      final leading = find
          .descendant(of: tile, matching: find.byType(Icon))
          .first;
      expect(tester.getRect(title).left, firstTitle.left);
      expect(tester.getRect(leading).left, 24);
      expect(
        tester.getRect(leading).center.dy,
        closeTo(tester.getRect(tile).center.dy, 0.5),
      );
      expect(
        tester.renderObject<RenderParagraph>(title).text.style?.fontSize,
        14,
      );
    }
    final arrow = tester.getRect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'WebDAV 备份 / 恢复'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    final toggle = tester.getRect(find.byType(Switch));
    expect(toggle.right, arrow.right);
    expect(toggle.width, greaterThanOrEqualTo(48));
    expect(toggle.height, greaterThanOrEqualTo(48));
    final wasDark = state.darkMode;
    await tester.tapAt(Offset(toggle.center.dx, toggle.top + 2));
    await tester.pumpAndSettle();
    expect(state.darkMode, !wasDark);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(state.darkMode, wasDark);
    expect(
      tester.getRect(find.byIcon(Icons.upload_file_outlined)).right,
      arrow.right,
    );
    await state.setAdBlock('{"urlRules":["tracking"]}');
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byIcon(Icons.delete_outline)).right,
      arrow.right,
    );
    final clear = tester.getRect(find.byTooltip('清除规则'));
    expect(clear.width, greaterThanOrEqualTo(48));
    expect(clear.height, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(clear.left + 2, clear.center.dy));
    await tester.pumpAndSettle();
    expect(state.adBlock, isNull);
    expect(tester.takeException(), isNull);
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
