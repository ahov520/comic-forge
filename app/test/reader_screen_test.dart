import 'dart:async';

import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fetcher.dart';

void main() {
  testWidgets('低高度大字号下可滚动到重试入口，导航保持可用', (tester) async {
    tester.view.physicalSize = const Size(320, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    final runtime = SourceRuntime(
      source: ComicSource.fromJson({
        'id': 'reader-small',
        'url': 'https://reader.example',
        'rules': {'contentUrl': '.page@src'},
      }),
      fetcher: FakeFetcher((uri) {
        if (uri.path == '/small/1043') attempts++;
        throw StateError('offline');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: runtime,
          book: Book(name: '很长的漫画书名包含特别篇和完整的番外故事'),
          chapters: List.generate(
            1300,
            (i) => Chapter(
              title: '第${i + 1}话',
              url: 'https://reader.example/small/$i',
            ),
          ),
          initialIndex: 1043,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重试'));
    expect(
      tester.getRect(find.widgetWithText(FilledButton, '重试')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ReaderBottomChrome)).top),
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('目录 · 1300 话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('失败和空章节保留话间导航，重试重新请求，旧响应不串话', (tester) async {
    final nextResponse = Completer<String>();
    var firstAttempts = 0;
    final fetcher = FakeFetcher((uri) {
      if (uri.path == '/recovery/2') return nextResponse.future;
      if (++firstAttempts == 1) throw StateError('offline');
      return '<html></html>';
    });
    final source = ComicSource.fromJson({
      'id': 'reader-recovery',
      'name': '阅读测试源',
      'url': 'https://reader.example',
      'rules': {'contentUrl': '.page@src'},
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ReaderScreen(
          runtime: SourceRuntime(source: source, fetcher: fetcher),
          book: Book(name: '漫画', bookUrl: 'https://reader.example/book'),
          chapters: [
            Chapter(title: '第一话', url: 'https://reader.example/recovery/1'),
            Chapter(title: '第二话', url: 'https://reader.example/recovery/2'),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时无法加载章节'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(firstAttempts, 2);
    expect(find.text('本话暂无图片'), findsOneWidget);
    expect(find.text('暂时无法加载章节'), findsNothing);

    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第二话'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('本话暂无图片'), findsNothing);
    expect(find.byType(SkeletonBox), findsOneWidget);

    await tester.tap(find.text('上一话'));
    await tester.pumpAndSettle();
    nextResponse.completeError(StateError('late chapter failure'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第一话'), findsOneWidget);
    expect(find.text('本话暂无图片'), findsOneWidget);
    expect(find.text('暂时无法加载章节'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('目录 · 2 话'), findsOneWidget);
    await tester.tap(find.text('第二话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第二话'), findsOneWidget);
    expect(find.text('暂时无法加载章节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
