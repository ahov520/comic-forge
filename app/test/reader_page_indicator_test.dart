import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';
import 'support/reader_test_images.dart';

String _html(String chapterUrl, int pages) => List.generate(
  pages,
  (i) => '<img class="page" src="$chapterUrl/page-$i.png">',
).join();

Future<(AppState, List<Chapter>)> _open(
  WidgetTester tester,
  String fixture, {
  bool paged = false,
  int chapters = 2,
  int pages = 5,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final state = AppState()..readerMode = paged ? 'paged' : 'scroll';
  addTearDown(state.dispose);
  final root = 'https://page-progress.example/$fixture';
  final chapterList = List.generate(
    chapters,
    (i) => Chapter(title: '第${i + 1}话', url: '$root/chapter-$i'),
  );
  await cacheReaderTestImages(tester, [
    for (final chapter in chapterList)
      for (var i = 0; i < pages; i++) '${chapter.url}/page-$i.png',
  ]);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
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
          fetcher: FakeFetcher((uri) => _html(uri.toString(), pages)),
        ),
        book: Book(name: '漫画', bookUrl: '$root/book'),
        chapters: chapterList,
        initialIndex: 0,
        appState: state,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (state, chapterList);
}

PageController _pages(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

Future<void> _seekSliderEnd(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const Key('reader-page-slider')));
  await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '翻页模式显示章内页码，拖进度条跳到末页并记住位置',
    (tester) async {
      final (state, chapters) = await _open(tester, 'paged-seek', paged: true);
      expect(find.byKey(const Key('reader-page-label')), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget, reason: '话间目录计数仍在');
      await _seekSliderEnd(tester);
      expect(_pages(tester).page, 4);
      expect(find.text('5/5'), findsOneWidget);
      expect(state.readerPageFor(chapters.first.url), 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '点页码打开跳页，输入序号落到指定页并关闭对话框',
    (tester) async {
      await _open(tester, 'paged-picker', paged: true);
      await tester.tap(find.byTooltip('跳转页码'));
      await tester.pumpAndSettle();
      expect(find.text('跳转页码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.widgetWithText(FilledButton, '跳转'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_pages(tester).page, 2);
      expect(find.text('3/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '滚动模式拖进度条跳到末页，目录与设置入口仍可用',
    (tester) async {
      await _open(tester, 'scroll-seek');
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
      await _seekSliderEnd(tester);
      expect(find.text('5/5'), findsOneWidget);
      expect(_scroll(tester).offset, greaterThan(0));
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      expect(find.text('目录 · 2 话'), findsOneWidget);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(find.text('音量键翻页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '收起工具栏后仍显示页码徽章，点按跳页',
    (tester) async {
      await _open(tester, 'immersive-badge', paged: true);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderTopChrome>(find.byType(ReaderTopChrome)).visible,
        isFalse,
      );
      expect(find.byKey(const Key('reader-page-badge')), findsOneWidget);
      expect(find.byKey(const Key('reader-page-bar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reader-page-badge')));
      await tester.pumpAndSettle();
      expect(find.text('跳转页码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '4');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(_pages(tester).page, 3);
      expect(find.text('4/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '空白或超出范围的页码明确提示，取消不改当前页',
    (tester) async {
      await _open(tester, 'page-jump-validate', paged: true);
      await tester.tap(find.byTooltip('跳转页码'));
      await tester.pumpAndSettle();
      for (final invalid in ['', '0', '6']) {
        await tester.enterText(find.byType(TextField), invalid);
        await tester.tap(find.widgetWithText(FilledButton, '跳转'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 1–5 之间的页码'), findsOneWidget);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_pages(tester).page, 0);
      expect(find.text('1/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '失败章节不显示页进度，加载成功后出现',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final state = AppState()..readerMode = 'paged';
      addTearDown(state.dispose);
      var fail = true;
      const root = 'https://page-progress.example/fail-then-load';
      const urls = ['$root/chapter/page-0.png', '$root/chapter/page-1.png'];
      await cacheReaderTestImages(tester, urls);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: ReaderScreen(
            runtime: SourceRuntime(
              source: ComicSource.fromJson({
                'id': 'fail-then-load',
                'url': root,
                'rules': {'contentUrl': '.page@src'},
              }),
              fetcher: FakeFetcher((_) {
                if (fail) throw StateError('offline');
                return urls
                    .map((url) => '<img class="page" src="$url">')
                    .join();
              }),
            ),
            book: Book(name: '漫画', bookUrl: '$root/book'),
            chapters: [Chapter(title: '第一话', url: '$root/chapter')],
            initialIndex: 0,
            appState: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法加载章节'), findsOneWidget);
      expect(find.byKey(const Key('reader-page-label')), findsNothing);
      expect(find.byKey(const Key('reader-page-slider')), findsNothing);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-page-label')), findsOneWidget);
      expect(find.text('1/2'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '窄屏大字号页进度与话间导航均可操作',
    (tester) async {
      await _open(tester, 'large-text', paged: true, textScale: 2);
      expect(
        find.byKey(const Key('reader-page-slider')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('下一话').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('跳转页码'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
