import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(String id) => ComicSource.fromJson({
  'id': id,
  'name': '源$id',
  'url': 'https://$id.example',
  'rules': {
    'searchUrl': '/search',
    'searchList': '.item',
    'searchName': '.t@text',
    'searchBookUrl': '.t@href',
  },
});

const _page = '<div class="item"><a class="t" href="/book">漫画</a></div>';

Finder _candidate(String sourceId) => find.byWidgetPredicate(
  (widget) => widget is BookTile && widget.book.sourceId == sourceId,
);

void main() {
  late SourceService service;
  late AppState state;
  late Book book;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    for (final id in ['current', 'first', 'second']) {
      await state.addSourceManual(_source(id));
    }
    book = Book(
      name: '漫画',
      sourceId: 'current',
      bookUrl: 'https://current.example/book',
    );
    respond = (_) => _page;
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

  Future<void> showDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async =>
              (book, [Chapter(title: '第一话', url: 'https://current.example/1')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('换源面板打开期间启停、删除和新增源会同步候选与命中角标', (tester) async {
    await showDetail(tester);
    await tester.tap(find.byTooltip('换源（2 源命中）'));
    await tester.pumpAndSettle();
    expect(_candidate('first'), findsOneWidget);
    expect(_candidate('second'), findsOneWidget);

    await state.toggleSource('first');
    await tester.pumpAndSettle();
    expect(_candidate('first'), findsNothing);
    expect(_candidate('second'), findsOneWidget);
    expect(find.byTooltip('换源（1 源命中）'), findsOneWidget);

    await state.removeSource('second');
    await tester.pumpAndSettle();
    expect(find.byType(BookTile), findsNothing);
    expect(find.text('其它源没有搜到同名书'), findsOneWidget);
    expect(find.byTooltip('换源（1 源命中）'), findsNothing);

    await state.addSourceManual(_source('third'));
    await tester.pumpAndSettle();
    expect(_candidate('third'), findsOneWidget);
    final requests = fetcher.requests.length;
    await state.toggleShelf(book);
    await tester.pumpAndSettle();
    expect(_candidate('third'), findsOneWidget);
    expect(fetcher.requests, hasLength(requests), reason: '收藏更新不重复扫描源');
    await tester.pumpWidget(const SizedBox.shrink());
    await state.toggleSource('third');
    expect(tester.takeException(), isNull);
  });

  testWidgets('候选范围已变更时，旧扫描晚到不会恢复旧命中数', (tester) async {
    final oldResponse = Completer<String>();
    respond = (uri) => uri.host == 'first.example' ? oldResponse.future : _page;
    await showDetail(tester);
    await state.toggleSource('first');
    await tester.pumpAndSettle();
    expect(find.byTooltip('换源（1 源命中）'), findsOneWidget);

    oldResponse.complete(_page);
    await tester.pumpAndSettle();
    expect(find.byTooltip('换源（1 源命中）'), findsOneWidget);
    expect(find.byTooltip('换源（2 源命中）'), findsNothing);
    await tester.tap(find.byTooltip('换源（1 源命中）'));
    await tester.pumpAndSettle();
    expect(_candidate('first'), findsNothing);
    expect(_candidate('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('换源全部失败显示错误并可原地重试，恢复后刷新命中数', (tester) async {
    respond = (_) => throw FetchException('offline');
    await showDetail(tester);
    await tester.tap(find.byTooltip('换源'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法查找其它来源'), findsOneWidget);
    expect(find.text('其它源没有搜到同名书'), findsNothing);
    final requests = fetcher.requests.length;
    respond = (_) => _page;
    await tester.tap(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(_candidate('first'), findsOneWidget);
    expect(_candidate('second'), findsOneWidget);
    expect(find.byTooltip('换源（2 源命中）'), findsOneWidget);
    expect(fetcher.requests, hasLength(requests + 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('换源无匹配时可重新查找，不会反复复用旧空结果', (tester) async {
    respond = (_) => '<html></html>';
    await showDetail(tester);
    await tester.tap(find.byTooltip('换源'));
    await tester.pumpAndSettle();
    expect(find.text('其它源没有搜到同名书'), findsOneWidget);
    expect(find.text('暂时无法查找其它来源'), findsNothing);
    final requests = fetcher.requests.length;
    respond = (_) => _page;
    await tester.tap(find.text('重新查找'));
    await tester.pumpAndSettle();
    expect(_candidate('first'), findsOneWidget);
    expect(_candidate('second'), findsOneWidget);
    expect(fetcher.requests, hasLength(requests + 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
