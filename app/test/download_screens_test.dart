import 'dart:async';
import 'dart:io';

import 'package:comic_forge/services/download_store.dart';
import 'package:comic_forge/services/image_cache_store.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/download_queue.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/download_selection_sheet.dart';
import 'package:comic_forge/ui/downloads_screen.dart';
import 'package:comic_forge/ui/reader_network_image.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_test_image.dart';
import 'support/fake_fetcher.dart';

class _FakeCacheManager extends Fake implements BaseCacheManager {
  var emptied = 0;
  final removed = <String>[];

  @override
  Future<void> emptyCache() async {
    emptied++;
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
  }
}

Future<void> _loadFileImage(String uri) async {
  final stream = FileImage(
    File.fromUri(Uri.parse(uri)),
  ).resolve(ImageConfiguration.empty);
  final loaded = Completer<void>();
  final listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!loaded.isCompleted) loaded.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!loaded.isCompleted) loaded.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await loaded.future;
  } finally {
    stream.removeListener(listener);
  }
}

Future<void> _pumpOfflineReader(WidgetTester tester, String uri) async {
  final image = find.byWidgetPredicate(
    (widget) => widget is ReaderNetworkImage && widget.imageUrl == uri,
  );
  // 文件系统在真实事件循环运行，逐帧让目录检查完成后再等待 UI 动画。
  for (var i = 0; i < 50 && image.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(image, findsOneWidget, reason: '阅读器应加载指定章节的本地文件');
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;
  late ComicSource source;
  late Book book;
  late List<Chapter> chapters;
  late SourceService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = ComicSource.fromJson({
      'id': 'download-screen',
      'name': '下载源',
      'url': 'https://download.example',
      'rules': <String, dynamic>{},
    });
    book = Book(
      sourceId: source.id,
      name: '漫画',
      bookUrl: 'https://download.example/book',
    );
    chapters = List.generate(
      4,
      (i) => Chapter(
        title: '第${i + 1}话',
        url: 'https://download.example/c${i + 1}',
      ),
    );
    service = SourceService.instance;
    service.debugClearSwitchCache();
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('详情倒序不影响未读选择，支持手动多选并进入下载管理', (tester) async {
    final queue = DownloadQueue(
      sourceFor: (_) => source,
      loadImages: (_, _) async => throw StateError('测试离线'),
    );
    state = AppState(downloadQueue: queue);
    await state.addSourceManual(source);
    await state.toggleShelf(book);
    await state.saveDetailCache(book, chapters);
    await state.saveProgress(
      book,
      chapterUrl: chapters[1].url,
      chapterTitle: chapters[1].title,
      chapterIndex: 1,
      chapterCount: chapters.length,
    );
    await state.clearShelfUpdate(book);
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async => (book, chapters),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量离线下载'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadSelectionSheet), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, chapters[i].title),
            )
            .value,
        i > 1,
      );
    }
    await tester.tap(find.widgetWithText(CheckboxListTile, chapters[2].title));
    await tester.tap(find.widgetWithText(CheckboxListTile, chapters[0].title));
    await tester.tap(find.text('加入下载队列（2 话）'));
    await tester.pumpAndSettle();
    expect(queue.tasks.map((task) => task.chapter.url), [
      chapters[0].url,
      chapters[3].url,
    ]);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
    expect(find.text('漫画 · 第1话'), findsOneWidget);
    expect(find.text('漫画 · 第4话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号下可选择未读、取消全选和提交', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    state = AppState(
      downloadQueue: DownloadQueue(
        sourceFor: (_) => source,
        loadImages: (_, _) async => throw StateError('测试离线'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: DownloadSelectionSheet(
            state: state,
            book: book,
            chapters: chapters,
          ),
        ),
      ),
    );
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('加入下载队列（0 话）'), findsOneWidget);
    await tester.tap(find.text('选中未读'));
    await tester.pumpAndSettle();
    expect(find.text('加入下载队列（4 话）').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载管理显示失败与进度，点击重试补图后可以删除文件', (tester) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('comic-forge-download-ui-'),
    );
    addTearDown(() async {
      await directory!.delete(recursive: true);
    });
    final store = DownloadStore(directory: () async => directory!);
    var shouldFail = true;
    final queue = DownloadQueue(
      sourceFor: (_) => source,
      store: store,
      loadImages: (_, _) async => (
        urls: ['https://download.example/page.png'],
        headers: <String, String>{},
      ),
      fetchBytes: (_, _) async {
        if (shouldFail) throw StateError('下载失败');
        return downloadTestImage();
      },
    );
    state = AppState(downloadQueue: queue);
    await tester.runAsync(() async {
      await queue.enqueue(book, chapters, [0]);
      await queue.idle;
    });
    await tester.pumpWidget(MaterialApp(home: DownloadsScreen(state: state)));
    expect(find.text('下载失败 · 0/1 张'), findsOneWidget);
    shouldFail = false;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('重试 第1话'));
      await queue.idle;
    });
    await tester.pumpAndSettle();
    expect(find.text('已下载 1 张 · 点击阅读'), findsOneWidget);
    final uri = (await tester.runAsync(
      () => queue.offlineImages(book, chapters[0]),
    ))!.single;
    final taskId = queue.tasks.single.id;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('删除 第1话 的下载'));
      await queue.remove(taskId);
    });
    await tester.pumpAndSettle();
    expect(find.text('还没有下载任务'), findsOneWidget);
    expect(
      await tester.runAsync(() => File.fromUri(Uri.parse(uri)).exists()),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['scroll', 'paged']) {
    testWidgets('重启断网后直接读取离线图片并跨话，保留原目录进度：$mode', (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-reader-offline-'),
      );
      addTearDown(() async {
        await directory!.delete(recursive: true);
      });
      final store = DownloadStore(directory: () async => directory!);
      final queue = DownloadQueue(
        sourceFor: (_) => source,
        store: store,
        loadImages: (_, chapter) async =>
            (urls: ['${chapter.url}/page.png'], headers: <String, String>{}),
        fetchBytes: (_, _) async => downloadTestImage(),
      );
      chapters = chapters.take(2).toList();
      await tester.runAsync(() async {
        await queue.enqueue(book, chapters, [0, 1]);
        await queue.idle;
      });
      queue.dispose();
      final restored = DownloadQueue(
        sourceFor: (_) => null,
        store: store,
        loadImages: (_, _) async => throw StateError('禁止重新解析下载章节'),
        fetchBytes: (_, _) async => throw StateError('禁止请求图片'),
      );
      state = AppState(downloadQueue: restored);
      state.readerMode = mode;
      final fetcher = FakeFetcher((_) => throw StateError('offline'));
      final runtime = SourceRuntime(source: source, fetcher: fetcher);
      final localImages = <String>[];
      await tester.runAsync(() async {
        await restored.load();
        for (final chapter in chapters) {
          for (final uri in (await restored.offlineImages(book, chapter))!) {
            localImages.add(uri);
            await _loadFileImage(uri);
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              runtime: runtime,
              book: book,
              chapters: chapters,
              initialIndex: 0,
              appState: state,
            ),
          ),
        );
        await tester.pump();
      });
      await _pumpOfflineReader(tester, localImages.first);
      expect(
        find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        findsWidgets,
      );
      expect(
        tester
            .widget<ReaderNetworkImage>(find.byType(ReaderNetworkImage).first)
            .imageUrl,
        startsWith('file:'),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('下一话'));
        await restored.offlineImages(book, chapters[1]);
      });
      await _pumpOfflineReader(tester, localImages.last);
      expect(find.text('漫画 · 第2话'), findsOneWidget);
      expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
      expect(state.progressFor(book.bookUrl)?.chapterCount, 2);
      expect(fetcher.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('源已移除且详情缓存已淘汰，仍可从目录和下载管理进入离线阅读', (tester) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('comic-forge-no-source-'),
    );
    addTearDown(() async {
      await directory!.delete(recursive: true);
    });
    final queue = DownloadQueue(
      sourceFor: (_) => null,
      store: DownloadStore(directory: () async => directory!),
      loadImages: (_, _) async => (
        urls: ['https://download.example/page.png'],
        headers: <String, String>{},
      ),
      fetchBytes: (_, _) async => downloadTestImage(),
    );
    state = AppState(downloadQueue: queue);
    late String localImage;
    await tester.runAsync(() async {
      await queue.enqueue(book, chapters, [3]);
      await queue.idle;
      localImage = (await queue.offlineImages(book, chapters[3]))!.single;
      await _loadFileImage(localImage);
    });
    expect(state.sources, isEmpty);
    expect(state.detailCache, isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(book: book, appState: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('离线阅读 4'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('离线阅读 4'));
      await queue.offlineImages(book, chapters[3]);
    });
    await _pumpOfflineReader(tester, localImage);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('漫画 · 第4话'), findsOneWidget);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 3);
    expect(state.progressFor(book.bookUrl)?.chapterCount, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('设置页提供可重新进入的下载管理入口', (tester) async {
    state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('下载管理'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载管理'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
    expect(find.text('还没有下载任务'), findsOneWidget);
  });

  testWidgets(
    '非 Android 不显示占用与清理菜单',
    (tester) async {
      state = AppState();
      await tester.pumpWidget(MaterialApp(home: DownloadsScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('清理存储'), findsNothing);
      expect(find.textContaining('图片缓存约'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'Android 显示占用，确认后清除失败不影响已完成离线文件，清除缓存不删下载',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-cleanup-ui-'),
      );
      final cacheDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-image-cache-ui-'),
      );
      addTearDown(() async {
        await directory!.delete(recursive: true);
        await cacheDir!.delete(recursive: true);
      });
      final store = DownloadStore(directory: () async => directory!);
      final cacheManager = _FakeCacheManager();
      var failSecond = true;
      final queue = DownloadQueue(
        sourceFor: (_) => source,
        store: store,
        loadImages: (_, chapter) async =>
            (urls: ['${chapter.url}/page.png'], headers: <String, String>{}),
        fetchBytes: (url, _) async {
          if (failSecond && url.contains('/c2/')) throw StateError('失败');
          return downloadTestImage();
        },
      );
      state = AppState(
        downloadQueue: queue,
        imageCache: ImageCacheStore(
          manager: cacheManager,
          directory: () async => cacheDir!,
        ),
      );
      await tester.runAsync(() async {
        await File(
          '${cacheDir!.path}/cached.bin',
        ).writeAsBytes(List.filled(120, 7));
        await queue.enqueue(book, chapters, [0, 1]);
        await queue.idle;
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: DownloadsScreen(state: state)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('离线约'), findsOneWidget);
      expect(find.textContaining('图片缓存约 120 B'), findsOneWidget);
      expect(find.text('已下载 1 张 · 点击阅读'), findsOneWidget);
      expect(find.text('下载失败 · 0/1 张'), findsOneWidget);

      await tester.tap(find.byTooltip('清理存储'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除失败任务'));
      await tester.pumpAndSettle();
      expect(find.text('将删除 1 条失败任务及其不完整文件。已完成的离线章节不受影响。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('下载失败 · 0/1 张'), findsOneWidget);

      await tester.tap(find.byTooltip('清理存储'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除失败任务'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('清除'));
        await queue.clearFailed();
      });
      await tester.pumpAndSettle();
      expect(find.text('下载失败 · 0/1 张'), findsNothing);
      expect(find.text('已下载 1 张 · 点击阅读'), findsOneWidget);
      final kept = await tester.runAsync(
        () => queue.offlineImages(book, chapters[0]),
      );
      expect(kept, isNotNull);
      expect(
        await tester.runAsync(
          () => File.fromUri(Uri.parse(kept!.single)).exists(),
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('清理存储'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除图片缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(cacheManager.emptied, 1);
      expect(
        await tester.runAsync(
          () => File.fromUri(Uri.parse(kept!.single)).exists(),
        ),
        isTrue,
      );
      expect(
        await tester.runAsync(() => queue.offlineImages(book, chapters[0])),
        kept,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Android 确认后按漫画删除离线文件，其它漫画仍可阅读',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-book-cleanup-'),
      );
      addTearDown(() async {
        await directory!.delete(recursive: true);
      });
      final other = Book(
        sourceId: source.id,
        name: '另一本',
        bookUrl: 'https://download.example/other',
      );
      final queue = DownloadQueue(
        sourceFor: (_) => source,
        store: DownloadStore(directory: () async => directory!),
        loadImages: (_, chapter) async =>
            (urls: ['${chapter.url}/page.png'], headers: <String, String>{}),
        fetchBytes: (_, _) async => downloadTestImage(),
      );
      state = AppState(
        downloadQueue: queue,
        imageCache: ImageCacheStore(manager: _FakeCacheManager()),
      );
      await tester.runAsync(() async {
        await queue.enqueue(book, chapters, [0]);
        await queue.enqueue(other, chapters, [0]);
        await queue.idle;
      });
      await tester.pumpWidget(MaterialApp(home: DownloadsScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清理存储'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按漫画清理离线文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('漫画'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将删除「漫画」的 1 话离线下载'), findsOneWidget);
      final bookKey = queue.taskFor(book, chapters[0])!.bookKey;
      await tester.runAsync(() async {
        await tester.tap(find.text('删除'));
        await queue.removeBook(bookKey);
      });
      await tester.pumpAndSettle();
      expect(find.text('漫画 · 第1话'), findsNothing);
      expect(find.text('另一本 · 第1话'), findsOneWidget);
      expect(
        await tester.runAsync(() => queue.offlineImages(book, chapters[0])),
        isNull,
      );
      expect(
        await tester.runAsync(() => queue.offlineImages(other, chapters[0])),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
