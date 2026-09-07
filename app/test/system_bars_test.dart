import 'dart:async';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

void main() {
  testWidgets('系统栏随深浅主题更新，离开阅读器后恢复首页颜色', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
    addTearDown(tester.view.resetPadding);
    SharedPreferences.setMockInitialValues({});
    final state = AppState()..darkMode = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    expect(
      SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
      Brightness.dark,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            runtime: SourceRuntime(
              source: ComicSource.fromJson({'id': 'system-bars'}),
              fetcher: FakeFetcher((_) => '<html></html>'),
            ),
            book: Book(name: '漫画'),
            chapters: [
              Chapter(title: '第一话', url: 'https://system-bars.example/1'),
            ],
            initialIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(
      SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
      Brightness.light,
    );

    navigator.pop();
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    expect(
      SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
      Brightness.dark,
    );
    await state.setDark(true);
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(
      SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
