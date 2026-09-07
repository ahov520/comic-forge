import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_chrome.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  testWidgets('横屏左右旋转后，关闭和设置工具条始终避让刘海并保持可操作', (tester) async {
    tester.view.physicalSize = const Size(720, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    final runtime = SourceRuntime(
      source: ComicSource.fromJson({
        'id': 'reader-safe-area',
        'url': 'https://reader.example',
      }),
      fetcher: FakeFetcher((_) => '<html></html>'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(
                      runtime: runtime,
                      book: Book(
                        name: '漫画',
                        bookUrl: '${runtime.source.url}/book',
                      ),
                      chapters: [
                        Chapter(
                          title: '第一话',
                          url: '${runtime.source.url}/safe',
                        ),
                      ],
                      initialIndex: 0,
                      appState: state,
                    ),
                  ),
                ),
                child: const Text('打开阅读器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开阅读器'));
    await tester.pumpAndSettle();

    for (final notch in [
      const FakeViewPadding(left: 60, bottom: 16),
      const FakeViewPadding(right: 60, bottom: 16),
    ]) {
      tester.view.padding = notch;
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ReaderTopChrome));
      expect(bar.left, greaterThanOrEqualTo(notch.left));
      expect(bar.right, lessThanOrEqualTo(720 - notch.right));
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      Navigator.of(tester.element(find.byType(Slider))).pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.text('打开阅读器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
