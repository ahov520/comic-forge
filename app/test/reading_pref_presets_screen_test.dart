import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reading_pref_presets_screen.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _showSettings(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(340, 1200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
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
  tearDown(() => state.dispose());

  testWidgets('设置页可保存、一点切换、重命名和删除阅读预设', (tester) async {
    await state.setReaderMode('paged');
    await state.setReaderBrightness(0.4);
    await state.setReaderVolumeKeys(true);
    await _showSettings(tester, state);
    expect(find.text('阅读预设'), findsOneWidget);
    expect(find.text('保存滚动/翻页、亮度和音量键'), findsOneWidget);
    await tester.tap(find.text('阅读预设'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingPrefPresetsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('保存当前为预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入预设名称'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '夜间翻页');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('夜间翻页'), findsOneWidget);
    expect(find.text('翻页 · 亮度 40% · 音量键开'), findsOneWidget);

    await state.setReaderMode('scroll');
    await state.setReaderBrightness(1);
    await state.setReaderVolumeKeys(false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);
    await tester.tap(find.text('夜间翻页'));
    await tester.pumpAndSettle();
    expect(state.readerMode, 'paged');
    expect(state.readerBrightness, 0.4);
    expect(state.readerVolumeKeys, isTrue);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byTooltip('夜间翻页的操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '平板夜间');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('平板夜间'), findsOneWidget);

    await tester.tap(find.byTooltip('平板夜间的操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读预设'), findsOneWidget);
    expect(state.readerMode, 'paged');
    expect(state.readerPresets.presets, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字号设置页仍可进入阅读预设', (tester) async {
    await _showSettings(
      tester,
      state,
      size: const Size(320, 640),
      textScale: 2,
    );
    await tester.scrollUntilVisible(find.text('阅读预设'), 160);
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读预设'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读预设'), findsOneWidget);
    expect(find.text('保存当前设置').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
