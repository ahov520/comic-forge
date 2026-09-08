import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

Future<void> _openReader(
  WidgetTester tester,
  AppState state,
  String fixture, {
  double textScale = 1,
}) async {
  final root = 'https://reader.example/$fixture';
  final urls = ['$root/page-1.png', '$root/page-2.png'];
  await cacheReaderTestImages(tester, urls);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: ReaderScreen(
        runtime: SourceRuntime(
          source: ComicSource.fromJson({
            'id': fixture,
            'url': root,
            'rules': {'contentUrl': '.page@src'},
          }),
          fetcher: FakeFetcher(
            (_) => urls.map((url) => '<img class="page" src="$url">').join(),
          ),
        ),
        book: Book(name: '漫画', bookUrl: '$root/book'),
        chapters: [Chapter(title: '第一话', url: '$root/chapter')],
        initialIndex: 0,
        appState: state,
      ),
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

  testWidgets('切换模式和调整亮度即时作用于正文，关闭设置后仍保留', (tester) async {
    await _openReader(tester, state, 'settings-live');
    expect(find.byType(ListView), findsOneWidget);
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻页'));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);

    await tester.drag(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Slider),
      ),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(state.readerBrightness, lessThan(1));
    await tester.tapAt(const Offset(10, 20));
    await tester.pumpAndSettle();
    expect(find.text('音量键翻页'), findsNothing);
    expect(find.byKey(const Key('reader-page-slider')), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReaderScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color ==
                  Colors.black.withValues(alpha: 1 - state.readerBrightness),
        ),
      ),
      findsOneWidget,
      reason: '设置关闭后正文仍保留调暗遮罩',
    );

    await state.setReaderMode('scroll');
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    '音量键开关立即同步原生通道，退出阅读器释放拦截',
    (tester) async {
      const channel = MethodChannel('comic-forge/reader');
      final calls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setVolumeKeysEnabled') {
          calls.add((call.arguments as Map)['enabled'] as bool);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _openReader(tester, state, 'volume-toggle');
      expect(calls, isEmpty);

      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音量键翻页'));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      await tester.tap(find.text('音量键翻页'));
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();

      await state.setReaderVolumeKeys(true);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(calls, [true, false, true, false]);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('低高度大字号设置面板可滚动并切换阅读模式', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReader(tester, state, 'settings-small', textScale: 2);
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('翻页'));
    await tester.tap(find.text('翻页'));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    await tester.ensureVisible(find.text('音量键翻页'));
    expect(find.text('音量键翻页').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
