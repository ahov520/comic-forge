import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  testWidgets('阅读下一话后返回详情，续读按钮与当前章节同步，重新进入不回到首话', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    final source = ComicSource.fromJson({
      'id': 'detail-resume',
      'name': '测试源',
      'url': 'https://resume.example',
      'rules': {'contentUrl': '.page@src'},
    });
    await state.addSourceManual(source);
    final service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: FakeFetcher((_) => '<html></html>'),
    );
    addTearDown(() {
      service.debugRuntimeOverride = null;
      service.debugClearSwitchCache();
    });
    final book = Book(
      name: '漫画',
      bookUrl: 'https://resume.example/book',
      sourceId: source.id,
    );
    final chapters = [
      Chapter(title: '第一话', url: 'https://resume.example/1'),
      Chapter(title: '第二话', url: 'https://resume.example/2'),
    ];
    var detailLoads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async {
            detailLoads++;
            return (book, chapters);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一话'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第二话'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('续读 2'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
    final current = tester.widget<ChapterTile>(
      find.widgetWithText(ChapterTile, '第二话'),
    );
    expect(current.isCurrent, isTrue);
    expect(detailLoads, 1, reason: '进度变化不应重新请求详情');
    await tester.tap(find.text('续读 2'));
    await tester.pumpAndSettle();
    expect(find.text('漫画 · 第二话'), findsOneWidget);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
