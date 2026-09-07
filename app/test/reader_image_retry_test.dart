import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

class _ImageCache extends Fake implements BaseCacheManager {
  _ImageCache(this.file);

  final File file;
  final requests = <(String, Map<String, String>)>[];
  final removed = <String>[];
  Completer<void>? eviction;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    requests.add((url, Map.of(headers ?? {})));
    if (removed.isEmpty) throw StateError('offline');
    yield FileInfo(file, FileSource.Online, DateTime(2030), url);
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    await eviction?.future;
  }
}

Future<File> _imageFile(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFFDDDDDD), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(240, 480));
  picture.dispose();
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  image!.dispose();
  return MemoryFileSystem().file('/page.png')
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _waitForImage(String url) async {
  final stream = CachedNetworkImageProvider(
    url,
  ).resolve(ImageConfiguration.empty);
  final done = Completer<void>();
  final listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!done.isCompleted) done.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  late AppState state;
  late _ImageCache cache;
  late FakeFetcher fetcher;
  late String imageUrl;

  Future<void> showReader(
    WidgetTester tester,
    String fixture, {
    Size size = const Size(320, 640),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    cache = _ImageCache(await _imageFile(tester));
    // 本测试文件在独立 isolate 中；直接替换，避免初始化真实磁盘缓存插件。
    CachedNetworkImageProvider.defaultCacheManager = cache;
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    imageUrl = 'https://image-retry.example/$fixture/page-1.png';
    final second = 'https://image-retry.example/$fixture/page-2.png';
    await cacheReaderTestImages(tester, [second]);
    fetcher = FakeFetcher(
      (_) =>
          '<img class="page" src="$imageUrl">'
          '<img class="page" src="$second">',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: ComicSource.fromJson({
              'id': fixture,
              'url': 'https://image-retry.example',
              'headers': {'Referer': 'https://image-retry.example/book'},
              'rules': {'contentUrl': '.page@src'},
            }),
            fetcher: fetcher,
          ),
          book: Book(name: '漫画', bookUrl: 'https://image-retry.example/book'),
          chapters: [
            Chapter(title: '第一话', url: 'https://image-retry.example/$fixture'),
          ],
          initialIndex: 0,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });
  tearDown(() => state.dispose());

  for (final mode in ['scroll', 'paged']) {
    testWidgets('单图失败可独立重试，保留本话与工具栏并携带源请求头：$mode', (tester) async {
      state.readerMode = mode;
      await showReader(tester, 'image-retry-$mode');
      expect(find.text('第 1 张图片加载失败'), findsOneWidget);
      expect(find.text('重试图片').hitTestable(), findsOneWidget);
      final controller = mode == 'paged'
          ? tester.widget<PageView>(find.byType(PageView)).controller!
          : tester.widget<ListView>(find.byType(ListView)).controller!;
      final position = controller.offset;
      await tester.runAsync(() async {
        await tester.tap(find.text('重试图片'));
        await tester.pump();
        await _waitForImage(imageUrl);
      });
      await tester.pumpAndSettle();

      expect(find.text('第 1 张图片加载失败'), findsNothing);
      expect(find.text('重试图片'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        findsWidgets,
      );
      expect(cache.removed, [imageUrl]);
      expect(cache.requests.map((r) => r.$1), [imageUrl, imageUrl]);
      expect(
        cache.requests.every(
          (r) => r.$2['Referer'] == 'https://image-retry.example/book',
        ),
        isTrue,
      );
      expect(fetcher.requests, hasLength(1), reason: '单图重试不重新抓取整话');
      expect(controller.offset, position);
      expect(
        tester.widget<ReaderTopChrome>(find.byType(ReaderTopChrome)).visible,
        isTrue,
        reason: '重试按钮不触发正文点击手势',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('低高度大字号的翻页错误提示可滚动到重试入口', (tester) async {
    state.readerMode = 'paged';
    await showReader(
      tester,
      'image-retry-small',
      size: const Size(320, 240),
      textScale: 2,
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('重试图片').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('缓存清理中禁用重复重试，离开阅读器后不再发起取图或更新界面', (tester) async {
    await showReader(tester, 'image-retry-dispose');
    cache.eviction = Completer<void>();
    await tester.tap(find.text('重试图片'));
    await tester.pump();
    expect(find.text('重试中…'), findsOneWidget);
    await tester.tap(find.text('重试中…'));
    await tester.pump();
    expect(cache.removed, [imageUrl]);
    await tester.pumpWidget(const SizedBox.shrink());
    cache.eviction!.complete();
    await tester.pumpAndSettle();
    expect(cache.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
