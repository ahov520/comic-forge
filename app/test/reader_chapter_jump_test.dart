import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

List<Chapter> _chapters() => List.generate(
  1300,
  (i) => Chapter(
    title: '第${i + 1}话',
    url: 'https://jump.example/chapter/${i + 1}',
  ),
);

void main() {
  testWidgets('目录可输入序号跳到指定话，首末话也更新阅读进度并关闭面板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    final book = Book(name: '漫画', bookUrl: 'https://jump.example/book');
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          runtime: SourceRuntime(
            source: ComicSource.fromJson({
              'id': 'chapter-jump',
              'url': 'https://jump.example',
            }),
            fetcher: FakeFetcher((_) => '<html></html>'),
          ),
          book: book,
          chapters: _chapters(),
          initialIndex: 1043,
          appState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final number in [1200, 1, 1300]) {
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('跳转章节'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '$number');
      if (number == 1) {
        await tester.tap(find.widgetWithText(FilledButton, '跳转'));
      } else {
        await tester.testTextInput.receiveAction(TextInputAction.go);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ReaderCatalogSheet), findsNothing);
      expect(find.text('漫画 · 第$number话'), findsOneWidget);
      expect(state.progressFor(book.bookUrl)!.chapterIndex, number - 1);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空白或超出范围的序号明确提示，取消不会选中其它话', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: ReaderCatalogSheet(
            chapters: _chapters(),
            currentIndex: 1043,
            onPick: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1044',
    );
    for (final invalid in ['', '0', '1301']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(find.widgetWithText(FilledButton, '跳转'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1300 之间的序号'), findsOneWidget);
      expect(picked, -1);
    }
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReaderCatalogSheet), findsOneWidget);
    expect(picked, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏大字号与键盘占位下，跳转输入和按钮可操作', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 80);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: ReaderCatalogSheet(
            chapters: _chapters(),
            currentIndex: 1043,
            onPick: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '700');
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();
    expect(picked, 699);
    expect(tester.takeException(), isNull);
  });
}
