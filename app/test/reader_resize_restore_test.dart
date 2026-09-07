import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_network_image.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

const _root = 'https://resize-reader.example';
const _chapter = '$_root/chapter';
final _urls = List.generate(8, (i) => '$_root/page-$i.png');

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

double _positionInPage(WidgetTester tester, int index) {
  final rect = tester.getRect(
    find.byWidgetPredicate(
      (widget) =>
          widget is ReaderNetworkImage && widget.imageUrl == _urls[index],
    ),
  );
  return -rect.top / rect.height;
}

void main() {
  late AppState state;
  late ComicSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'resize-reader',
      'url': _root,
      'rules': {'contentUrl': '.page@src'},
    });
    await state.addSourceManual(source);
    SourceService.instance.debugClearSwitchCache();
  });
  tearDown(() {
    state.dispose();
    SourceService.instance.debugClearSwitchCache();
  });

  Future<void> showReader(WidgetTester tester, AppState current) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: source,
            fetcher: FakeFetcher(
              (_) => _urls.map((url) => '<img class="page" src="$url">').join(),
            ),
          ),
          book: Book(name: '续读漫画', bookUrl: '$_root/book'),
          chapters: [Chapter(title: '第一话', url: _chapter)],
          initialIndex: 0,
          appState: current,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 36);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await cacheReaderTestImages(tester, _urls);
  }

  test('旧版不含尺寸的记录仍按像素恢复，异常尺寸也不会阻断读取', () async {
    SharedPreferences.setMockInitialValues({
      'cf.scrollOffsets':
          '{"legacy":{"v":900,"at":1},"invalid":{"v":600,"at":2,"w":0,"top":-1}}',
    });
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.scrollOffsetFor('legacy', viewportWidth: 640), 900);
    expect(restored.scrollOffsetFor('invalid', viewportWidth: 640), 600);
  });

  testWidgets('横竖屏切换保留同一漫画页的位置，包含前面图片已离开布局的情况', (tester) async {
    await prepare(tester);
    await showReader(tester, state);
    final imageHeight = tester
        .getSize(find.byType(ReaderNetworkImage).first)
        .height;
    // 跳到后半章，使前面的图片已经离开懒加载列表。
    _scroll(tester).jumpTo(36 + imageHeight * 5.4);
    await tester.pumpAndSettle();
    final fraction = _positionInPage(tester, 5);
    expect(fraction, closeTo(0.4, 0.01));

    tester.view.physicalSize = const Size(640, 320);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(_positionInPage(tester, 5), closeTo(fraction, 0.01));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 128),
      ),
    );
    await tester.pumpAndSettle();
    final continued = _positionInPage(tester, 5);
    expect(continued, greaterThan(fraction));

    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 36);
    await tester.pumpAndSettle();
    expect(_positionInPage(tester, 5), closeTo(continued, 0.01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横屏保存后重启到竖屏，按宽度和顶部留白恢复原页内位置', (tester) async {
    await prepare(tester);
    tester.view.physicalSize = const Size(640, 320);
    tester.view.padding = FakeViewPadding.zero;
    await showReader(tester, state);
    final imageHeight = tester
        .getSize(find.byType(ReaderNetworkImage).first)
        .height;
    _scroll(tester).jumpTo(imageHeight * 2.4);
    await tester.pumpAndSettle();
    final fraction = _positionInPage(tester, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      state.scrollOffsetFor(_chapter),
      isNotNull,
      reason: '离页时尚未达到保存延时，也应保存最后的阅读位置',
    );
    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 36);
    await showReader(tester, restarted);
    expect(_positionInPage(tester, 2), closeTo(fraction, 0.01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
