import 'dart:async';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

String _html(String chapterUrl) => List.generate(
  3,
  (i) => '<img class="page" src="$chapterUrl/page-$i.png">',
).join();

Future<(AppState, List<Chapter>)> _open(
  WidgetTester tester,
  String fixture, {
  bool paged = false,
  Completer<String>? firstResponse,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final state = AppState()
    ..readerMode = paged ? 'paged' : 'scroll'
    ..readerVolumeKeys = true;
  addTearDown(state.dispose);
  const channel = MethodChannel('comic-forge/reader');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final root = 'https://navigation.example/$fixture';
  final chapters = List.generate(
    3,
    (i) => Chapter(title: '第${i + 1}话', url: '$root/chapter-$i'),
  );
  await cacheReaderTestImages(tester, [
    for (final chapter in chapters)
      for (var i = 0; i < 3; i++) '${chapter.url}/page-$i.png',
  ]);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
            (uri) =>
                firstResponse != null && uri.toString() == chapters.first.url
                ? firstResponse.future
                : _html(uri.toString()),
          ),
        ),
        book: Book(name: '漫画', bookUrl: '$root/book'),
        chapters: chapters,
        initialIndex: 0,
        appState: state,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (state, chapters);
}

Future<void> _volume(WidgetTester tester, String method) async {
  final delivered = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    'comic-forge/reader',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    (_) => delivered.complete(),
  );
  await delivered.future;
  await tester.pumpAndSettle();
}

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

PageController _pages(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

void main() {
  testWidgets('音量键先逐屏滚动，到话尾才切换下一话', (tester) async {
    await _open(tester, 'scroll-volume');
    await _volume(tester, 'volumeDown');
    expect(find.text('漫画 · 第1话'), findsOneWidget);
    expect(_scroll(tester).offset, greaterThan(0));
    await _volume(tester, 'volumeUp');
    expect(_scroll(tester).offset, closeTo(0, 0.1));

    final scroll = _scroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await _volume(tester, 'volumeDown');
    expect(find.text('漫画 · 第2话'), findsOneWidget);
    expect(_scroll(tester).offset, closeTo(0, 0.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('翻页模式音量键可跨话，新话从首图开始，末话不会越界', (tester) async {
    await _open(tester, 'paged-volume', paged: true);
    await _volume(tester, 'volumeUp');
    expect(_pages(tester).page, 0);
    await _volume(tester, 'volumeDown');
    expect(_pages(tester).page, 1);
    await _volume(tester, 'volumeDown');
    expect(_pages(tester).page, 2);
    await _volume(tester, 'volumeDown');
    expect(find.text('漫画 · 第2话'), findsOneWidget);
    expect(_pages(tester).page, 0);

    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第3话'), findsOneWidget);
    expect(_pages(tester).page, 0);
    for (var i = 0; i < 3; i++) {
      await _volume(tester, 'volumeDown');
    }
    expect(find.text('漫画 · 第3话'), findsOneWidget);
    expect(_pages(tester).page, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('章节加载期间音量键安全等待，加载后仍可正常翻页', (tester) async {
    final response = Completer<String>();
    final (_, chapters) = await _open(
      tester,
      'loading-volume',
      paged: true,
      firstResponse: response,
    );
    await _volume(tester, 'volumeDown');
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(tester.takeException(), isNull);
    response.complete(_html(chapters.first.url));
    await tester.pumpAndSettle();
    await _volume(tester, 'volumeDown');
    expect(_pages(tester).page, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('切话和切换模式前保存未到节流时间的位置，返回原话可恢复', (tester) async {
    final (state, chapters) = await _open(tester, 'save-before-leaving');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    final saved = state.scrollOffsetFor(chapters.first.url)!;
    expect(saved, greaterThan(0));
    expect(_scroll(tester).offset, closeTo(0, 0.1));
    await tester.tap(find.text('上一话'));
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(saved, 0.1));

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await state.setReaderMode('paged');
    await tester.pumpAndSettle();
    final beforeModeChange = state.scrollOffsetFor(chapters.first.url)!;
    expect(beforeModeChange, greaterThan(saved));
    await state.setReaderMode('scroll');
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, closeTo(beforeModeChange, 0.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
