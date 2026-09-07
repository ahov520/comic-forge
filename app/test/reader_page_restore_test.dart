import 'dart:async';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_image_page.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

const _root = 'https://page-restore.example.com';
final _chapters = List.generate(
  2,
  (i) => Chapter(title: '第${i + 1}话', url: '$_root/chapter-$i'),
);

String _html(String chapterUrl) => List.generate(
  3,
  (i) => '<img class="page" src="$chapterUrl/page-$i.png">',
).join();

PageController _pages(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

void main() {
  late AppState state;
  late SourceRuntime runtime;
  late FutureOr<String> Function(Uri) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.setReaderMode('paged');
    final source = ComicSource.fromJson({
      'id': 'page-restore',
      'url': _root,
      'rules': {'contentUrl': '.page@src'},
    });
    await state.addSourceManual(source);
    respond = (uri) => _html(uri.toString());
    runtime = SourceRuntime(
      source: source,
      fetcher: FakeFetcher((uri) => respond(uri)),
    );
  });
  tearDown(() => state.dispose());

  Future<void> showReader(WidgetTester tester, AppState appState) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await cacheReaderTestImages(tester, [
      for (final chapter in _chapters)
        for (var i = 0; i < 3; i++) '${chapter.url}/page-$i.png',
    ]);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: runtime,
          book: Book(name: '续读漫画', bookUrl: '$_root/book'),
          chapters: _chapters,
          initialIndex: 0,
          appState: appState,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('章内页码按话记忆，切话、切换模式和重启后直接从已读页继续', (tester) async {
    await showReader(tester, state);
    _pages(tester).jumpToPage(2);
    await tester.pumpAndSettle();
    expect(state.readerPageFor(_chapters.first.url), 2);

    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 0);
    _pages(tester).jumpToPage(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一话'));
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 2);
    expect(_pages(tester).initialPage, 2, reason: '首帧即使用续读页，不先显示第一张');

    await state.setReaderMode('scroll');
    await tester.pumpAndSettle();
    await state.setReaderMode('paged');
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 2);
    expect(
      tester
          .widgetList<ReaderImagePage>(find.byType(ReaderImagePage))
          .where((page) => page.active),
      hasLength(1),
      reason: '恢复页仍是唯一可响应缩放和翻页手势的当前页',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    await showReader(tester, restored);
    expect(_pages(tester).page, 2);
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('保存页码超出新图片列表时落到末页并修正记忆，仍能向前翻', (tester) async {
    await state.saveReaderPage(_chapters.first.url, 20);
    await showReader(tester, state);
    expect(_pages(tester).initialPage, 2);
    expect(_pages(tester).page, 2);
    expect(state.readerPageFor(_chapters.first.url), 2);
    await tester.tapAt(
      tester.getCenter(find.byType(PageView)) - const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 1);
    expect(state.readerPageFor(_chapters.first.url), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('加载期间切话，旧话晚到不会覆盖当前话的续读页码', (tester) async {
    final response = Completer<String>();
    respond = (uri) => uri.toString() == _chapters.first.url
        ? response.future
        : _html(uri.toString());
    await state.saveReaderPage(_chapters.first.url, 1);
    await state.saveReaderPage(_chapters.last.url, 2);
    await showReader(tester, state);
    expect(find.byType(PageView), findsNothing);
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(_pages(tester).page, 2);
    response.complete(_html(_chapters.first.url));
    await tester.pumpAndSettle();
    expect(find.text('续读漫画 · 第2话'), findsOneWidget);
    expect(_pages(tester).page, 2);
    expect(state.readerPageFor(_chapters.first.url), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
