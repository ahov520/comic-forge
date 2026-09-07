import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_image_page.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is ReaderImagePage && widget.active,
        ),
        matching: find.byType(InteractiveViewer),
      ),
    );

Future<void> _pinch(WidgetTester tester, double from, double to) async {
  final center = tester.getCenter(find.byType(PageView));
  final left = await tester.createGesture(pointer: 1);
  final right = await tester.createGesture(pointer: 2);
  await left.down(center - Offset(from, 0));
  await right.down(center + Offset(from, 0));
  await tester.pump();
  for (var step = 1; step <= 5; step++) {
    final distance = from + (to - from) * step / 5;
    await left.moveTo(center - Offset(distance, 0));
    await right.moveTo(center + Offset(distance, 0));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await left.up();
  await right.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('双指缩放后可拖动图片，复原后保留横滑与三分点击翻页', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = AppState()..readerMode = 'paged';
    addTearDown(state.dispose);
    const urls = [
      'https://gestures.example/1.png',
      'https://gestures.example/2.png',
    ];
    await cacheReaderTestImages(tester, urls);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: ComicSource.fromJson({
              'id': 'reader-gestures',
              'url': 'https://gestures.example',
              'rules': {'contentUrl': '.page@src'},
            }),
            fetcher: FakeFetcher(
              (_) => urls.map((url) => '<img class="page" src="$url">').join(),
            ),
          ),
          book: Book(name: '漫画', bookUrl: 'https://gestures.example/book'),
          chapters: [
            Chapter(title: '第一话', url: 'https://gestures.example/chapter'),
          ],
          initialIndex: 0,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    double page() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    double scale() =>
        _viewer(tester).transformationController!.value.getMaxScaleOnAxis();

    await _pinch(tester, 40, 110);
    expect(scale(), greaterThan(1.1));
    expect(page(), 0);
    final beforePan = _viewer(
      tester,
    ).transformationController!.value.getTranslation().x;
    await tester.drag(find.byType(PageView), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(page(), 0, reason: '放大后横向拖动应移动图片');
    expect(
      _viewer(tester).transformationController!.value.getTranslation().x,
      isNot(beforePan),
    );

    final center = tester.getCenter(find.byType(PageView));
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(page(), 1);
    await tester.tapAt(center - const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(page(), 0);
    expect(scale(), 1, reason: '放大状态下切页，返回时也应复原');
    await _pinch(tester, 40, 110);
    await tester.tapAt(center + const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(page(), 0, reason: '放大时点按边缘不应误翻页');
    expect(
      tester.widget<ReaderTopChrome>(find.byType(ReaderTopChrome)).visible,
      isFalse,
    );
    await _pinch(tester, 110, 10);
    expect(scale(), closeTo(1, 0.01));

    await tester.drag(find.byType(PageView), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(page(), 1, reason: '复原后恢复横向翻页');
    expect(scale(), 1);
    await tester.tapAt(center - const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(page(), 0);
    expect(scale(), 1, reason: '返回旧页时已恢复正常倍率');
    await tester.tapAt(center + const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(page(), 1);
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderTopChrome>(find.byType(ReaderTopChrome)).visible,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
