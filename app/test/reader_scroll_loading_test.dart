import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

class _DeferredImage extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image));
}

const _chapterUrl = 'https://scroll-loading.example/chapter';
ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

void main() {
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.saveScrollOffset(_chapterUrl, 900);
    SourceService.instance.debugClearSwitchCache();
  });
  tearDown(() {
    state.dispose();
    SourceService.instance.debugClearSwitchCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<List<VoidCallback>> showReader(
    WidgetTester tester, {
    bool volume = false,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    state.readerVolumeKeys = volume;
    const channel = MethodChannel('comic-forge/reader');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.grey, BlendMode.src);
    final picture = recorder.endRecording();
    final bitmap = await tester.runAsync(() => picture.toImage(240, 480));
    picture.dispose();
    addTearDown(bitmap!.dispose);
    final urls = List.generate(3, (i) => '$_chapterUrl/page-$i.png');
    final ready = <VoidCallback>[];
    for (final url in urls) {
      final completer = _DeferredImage();
      PaintingBinding.instance.imageCache.putIfAbsent(
        CachedNetworkImageProvider(url),
        () => completer,
      );
      ready.add(() => completer.complete(bitmap.clone()));
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: ComicSource.fromJson({
              'id': 'scroll-loading',
              'url': 'https://scroll-loading.example',
              'rules': {'contentUrl': '.page@src'},
            }),
            fetcher: FakeFetcher(
              (_) => urls.map((url) => '<img class="page" src="$url">').join(),
            ),
          ),
          book: Book(
            name: '续读漫画',
            bookUrl: 'https://scroll-loading.example/book',
          ),
          chapters: [Chapter(title: '第一话', url: _chapterUrl)],
          initialIndex: 0,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ready;
  }

  testWidgets('图片逐步展开后继续恢复保存位置，不把首帧截短的位置写回', (tester) async {
    final ready = await showReader(tester);
    expect(_scroll(tester).position.maxScrollExtent, lessThan(900));
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.scrollOffsetFor(_chapterUrl), 900);
    ready[0]();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, lessThan(900));
    expect(state.scrollOffsetFor(_chapterUrl), 900);
    ready[1]();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(900, 0.1));
    ready[2]();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(900, 0.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final volume in [false, true]) {
    testWidgets('用户${volume ? '按音量键' : '拖动'}后由用户位置接管，晚到图片不再触发旧恢复', (
      tester,
    ) async {
      final ready = await showReader(tester, volume: volume);
      if (volume) {
        final delivered = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          'comic-forge/reader',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('volumeUp'),
          ),
          (_) => delivered.complete(),
        );
        await delivered.future;
      } else {
        await tester.drag(find.byType(ListView), const Offset(0, 100));
      }
      await tester.pumpAndSettle();
      final chosen = _scroll(tester).offset;
      expect(chosen, lessThan(100));
      for (final resolve in ready) {
        resolve();
      }
      await tester.pumpAndSettle();
      expect(_scroll(tester).offset, closeTo(chosen, 0.1));
      await tester.pump(const Duration(milliseconds: 700));
      expect(state.scrollOffsetFor(_chapterUrl), closeTo(chosen, 0.1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('图片未展开就离开时保留原续读位置', (tester) async {
    await showReader(tester);
    expect(_scroll(tester).offset, lessThan(900));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.scrollOffsetFor(_chapterUrl), 900);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片加载途中旋转屏幕，原目标随宽度换算且不写入临时截短值', (tester) async {
    final ready = await showReader(tester);
    tester.view.physicalSize = const Size(640, 320);
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, lessThan(1800));
    expect(state.scrollOffsetFor(_chapterUrl), 1800);
    ready[0]();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, lessThan(1800));
    ready[1]();
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(1800, 0.1));
    ready[2]();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(900, 0.1));
    expect(state.scrollOffsetFor(_chapterUrl), 900);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.scrollOffsetFor(_chapterUrl), 900);
    expect(tester.takeException(), isNull);
  });
}
