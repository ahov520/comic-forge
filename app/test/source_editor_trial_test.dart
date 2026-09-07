import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/source_editor_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

const _books =
    '<div class="book"><a href="/book-a">漫画甲</a></div>'
    '<div class="book"><a href="/book-b">漫画乙</a></div>';
const _chapters =
    '<a class="chapter" href="/chapter-a">第一话</a>'
    '<a class="chapter" href="/chapter-b">第二话</a>';
const _newImages =
    '<img class="page" src="/new-1.png">'
    '<img class="page" src="/new-2.png">';

Finder get _keyword => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '试跑关键词',
);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

Future<void> _search(WidgetTester tester, [String keyword = '漫画']) async {
  await tester.ensureVisible(_keyword);
  await tester.enterText(_keyword, keyword);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  late SourceService service;
  late AppState state;
  late ComicSource source;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri) respond;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'trial-source',
      'name': '试跑源',
      'url': 'https://trial.example.com',
      'rules': {
        'searchUrl': '/search?q=searchKey',
        'searchList': '.book',
        'searchName': 'a@text',
        'searchBookUrl': 'a@href',
        'chapterList': '.chapter',
        'chapterName': '@text',
        'chapterUrl': '@href',
        'contentUrl': '.page@src',
      },
    });
    respond = (uri) => uri.path == '/search' ? _books : _chapters;
    fetcher = FakeFetcher((uri) => respond(uri));
    service = SourceService.instance;
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<void> showTrial(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SourceEditorScreen(state: state, source: source),
      ),
    );
    await tester.tap(find.text('基本信息'));
    await tester.pumpAndSettle();
  }

  for (final stage in ['搜索', '目录', '取图']) {
    for (final fails in [false, true]) {
      testWidgets('$stage 期间离页，延迟${fails ? '失败' : '成功'}不再更新已销毁页面', (
        tester,
      ) async {
        final pending = Completer<String>();
        final path = switch (stage) {
          '搜索' => '/search',
          '目录' => '/book-a',
          _ => '/chapter-a',
        };
        respond = (uri) => uri.path == path
            ? pending.future
            : uri.path == '/search'
            ? _books
            : _chapters;
        await showTrial(tester);
        await _search(tester);
        if (stage != '搜索') {
          await tester.pumpAndSettle();
          await _tap(tester, '漫画甲');
        }
        if (stage == '取图') {
          await tester.pumpAndSettle();
          await _tap(tester, '第一话');
        }
        expect(fetcher.requests.last.path, path);
        await tester.pumpWidget(const SizedBox.shrink());
        if (fails) {
          pending.completeError(FetchException('offline'));
        } else {
          pending.complete(
            stage == '搜索'
                ? _books
                : stage == '目录'
                ? _chapters
                : _newImages,
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('键盘再次提交搜索，旧请求失败不会结束新请求的加载或显示旧错误', (tester) async {
    final old = Completer<String>();
    final current = Completer<String>();
    respond = (uri) =>
        uri.queryParameters['q'] == '旧词' ? old.future : current.future;
    await showTrial(tester);
    await _search(tester, '旧词');
    await _search(tester, '新词');
    expect(fetcher.requests, hasLength(2));
    old.completeError(FetchException('old search failed'));
    await tester.pump();
    expect(find.textContaining('搜索失败'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    current.complete(_books);
    await tester.pumpAndSettle();
    expect(find.text('漫画甲'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('快速切换漫画，旧目录${fails ? '失败' : '晚到'}不会覆盖当前选择', (tester) async {
      final old = Completer<String>();
      respond = (uri) => switch (uri.path) {
        '/search' => _books,
        '/book-a' => old.future,
        _ => '<a class="chapter" href="/book-b-first">乙的第一话</a>',
      };
      await showTrial(tester);
      await _search(tester);
      await tester.pumpAndSettle();
      await _tap(tester, '漫画甲');
      await _tap(tester, '漫画乙');
      await tester.pumpAndSettle();
      expect(find.textContaining('目录「漫画乙」'), findsOneWidget);
      if (fails) {
        old.completeError(FetchException('old detail failed'));
      } else {
        old.complete(_chapters);
      }
      await tester.pumpAndSettle();
      expect(find.text('乙的第一话'), findsOneWidget);
      expect(find.text('第一话'), findsNothing);
      expect(find.textContaining('目录失败'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('快速换话只显示新话图片，重新搜索会清除旧取图的加载状态', (tester) async {
    var old = Completer<String>();
    respond = (uri) => switch (uri.path) {
      '/search' => _books,
      '/chapter-a' => old.future,
      '/chapter-b' => _newImages,
      _ => _chapters,
    };
    await showTrial(tester);
    await _search(tester);
    await tester.pumpAndSettle();
    await _tap(tester, '漫画甲');
    await tester.pumpAndSettle();
    await _tap(tester, '第一话');
    await _tap(tester, '第二话');
    await tester.pumpAndSettle();
    expect(find.text('取图成功：2 张'), findsOneWidget);
    old.complete('<img class="page" src="/old.png">');
    await tester.pumpAndSettle();
    expect(find.text('取图成功：2 张'), findsOneWidget);
    expect(find.textContaining('/old.png'), findsNothing);

    old = Completer<String>();
    await _tap(tester, '第一话');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _search(tester, '重新搜索');
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('目录「'), findsNothing);
    expect(find.textContaining('取图成功'), findsNothing);
    old.completeError(FetchException('old images failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('取图失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
