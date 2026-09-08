import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comic_forge/main.dart';
import 'package:comic_forge/services/download_store.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/download_queue.dart';
import 'package:comic_forge/state/reading_history.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/reader_network_image.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/reading_history_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_test_image.dart';
import 'support/fake_fetcher.dart';

class _HistoryRuntime extends SourceRuntime {
  _HistoryRuntime(ComicSource source, this.loadDetail)
    : super(source: source, fetcher: FakeFetcher((_) => '<html></html>'));

  final Future<(Book, List<Chapter>)> Function(String) loadDetail;

  @override
  Future<(Book, List<Chapter>)> detail(String bookUrl) => loadDetail(bookUrl);
}

void main() {
  late AppState state;
  late ComicSource source;
  late Book book;
  late List<Chapter> chapters;
  late SourceService service;
  var detailCalls = 0;

  Future<void> record({int index = 1}) => state.saveProgress(
    book,
    chapterUrl: chapters[index].url,
    chapterTitle: chapters[index].title,
    chapterIndex: index,
    chapterCount: chapters.length,
  );

  Future<void> showHistory(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ReadingHistoryScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    source = ComicSource.fromJson({
      'id': 'history-ui',
      'name': '历史源',
      'url': 'https://history.example',
      'rules': {'contentUrl': '.page@src'},
    });
    state = AppState();
    await state.addSourceManual(source);
    book = Book(
      sourceId: source.id,
      name: '历史漫画',
      bookUrl: 'https://history.example/book',
    );
    chapters = List.generate(
      4,
      (i) => Chapter(
        title: '第${i + 1}话',
        url: 'https://history.example/c${i + 1}',
      ),
    );
    service = SourceService.instance;
    service.debugClearSwitchCache();
    detailCalls = 0;
    service.debugRuntimeOverride = (source) =>
        _HistoryRuntime(source, (_) async {
          detailCalls++;
          return (book, chapters);
        });
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('时间线按今天、昨天和日期分组，新记录在前', (tester) async {
    final now = DateTime.now();
    final days = [
      DateTime(now.year, now.month, now.day, 12),
      DateTime(now.year, now.month, now.day - 1, 12),
      DateTime(now.year, now.month, now.day - 2, 12),
    ];
    final entries = List.generate(
      3,
      (i) => ReadingHistoryEntry(
        book: Book(
          name: '第 $i 天漫画',
          bookUrl: '/history-$i',
          sourceId: source.id,
        ),
        chapter: chapters[1],
        chapterIndex: 1,
        chapterCount: 4,
        at: days[i].millisecondsSinceEpoch,
      ),
    );
    await (await SharedPreferences.getInstance()).setString(
      'cf.readingHistory',
      jsonEncode(entries.reversed.map((entry) => entry.toJson()).toList()),
    );
    await state.load();
    await showHistory(tester);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(
      find.text(readingHistoryDay(days[2].millisecondsSinceEpoch)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('第 0 天漫画')).dy,
      lessThan(tester.getTopLeft(find.text('第 1 天漫画')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('按漫画名、章节或来源搜索，忽略大小写和首尾空格，清空后恢复日期分组', (tester) async {
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'moon',
        'name': '月亮源',
        'rules': <String, dynamic>{},
      }),
    );
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    final entries = [
      ReadingHistoryEntry(
        book: book,
        chapter: chapters[1],
        chapterIndex: 1,
        chapterCount: 4,
        at: now.millisecondsSinceEpoch,
      ),
      ReadingHistoryEntry(
        book: Book(name: 'Moon 漫画', sourceId: 'moon', bookUrl: '/moon'),
        chapter: Chapter(title: '番外篇', url: '/extra'),
        chapterIndex: 0,
        chapterCount: 1,
        at: yesterday.millisecondsSinceEpoch,
      ),
      ReadingHistoryEntry(
        book: Book(name: '山海卷', sourceId: 'removed', bookUrl: '/gone'),
        chapter: Chapter(url: '/first'),
        chapterIndex: 0,
        chapterCount: 1,
        at: yesterday.millisecondsSinceEpoch,
      ),
    ];
    await (await SharedPreferences.getInstance()).setString(
      'cf.readingHistory',
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    await state.load();
    await showHistory(tester);
    final search = find.byType(TextField);
    for (final query in ['  mOoN  ', '番外', '月亮源']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(find.text('Moon 漫画'), findsOneWidget);
      expect(find.text('历史漫画'), findsNothing);
      expect(find.text('山海卷'), findsNothing);
      expect(find.text('今天'), findsNothing);
      expect(find.text('昨天'), findsOneWidget);
    }
    await tester.enterText(search, '来源已移除');
    await tester.pumpAndSettle();
    expect(find.text('山海卷'), findsOneWidget);
    expect(find.text('Moon 漫画'), findsNothing);
    await tester.enterText(search, '第 1 话');
    await tester.pumpAndSettle();
    expect(find.text('山海卷'), findsOneWidget);
    await tester.enterText(search, '没有这本漫画');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的阅读记录'), findsOneWidget);
    expect(state.readingHistory, hasLength(3));
    expect(detailCalls, 0, reason: '搜索仅过滤本地历史');
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('历史漫画'), findsOneWidget);
    expect(find.text('Moon 漫画'), findsOneWidget);
    expect(find.text('山海卷'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('长列表滚动后切换搜索词会从匹配结果顶部显示', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = List.generate(
      20,
      (index) => ReadingHistoryEntry(
        book: Book(
          name: '合辑 $index',
          sourceId: source.id,
          bookUrl: '/collection-$index',
        ),
        chapter: chapters.first,
        chapterIndex: 0,
        chapterCount: 4,
        at: now - index * 1000,
      ),
    );
    await (await SharedPreferences.getInstance()).setString(
      'cf.readingHistory',
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    await state.load();
    await showHistory(tester);
    await tester.scrollUntilVisible(
      find.text('合辑 19'),
      400,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('合辑 0').hitTestable(), findsNothing);
    await tester.enterText(find.byType(TextField), '合辑');
    await tester.pumpAndSettle();
    expect(find.text('合辑 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索结果可续读，返回后保留查询，移除命中项不影响其余历史或阅读进度', (tester) async {
    await record();
    await state.saveDetailCache(book, chapters);
    await state.saveProgress(
      Book(name: '保留漫画', sourceId: source.id, bookUrl: '/other'),
      chapterUrl: '/other-c1',
      chapterTitle: '第一话',
      chapterIndex: 0,
      chapterCount: 1,
    );
    await showHistory(tester);
    await tester.enterText(find.byType(TextField), '历史漫画');
    await tester.pumpAndSettle();
    expect(find.text('保留漫画'), findsNothing);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pumpAndSettle();
    expect(find.text('历史漫画 · 第2话'), findsOneWidget);
    expect(detailCalls, 0);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '历史漫画',
    );
    await tester.tap(find.byTooltip('移除 历史漫画 的阅读记录'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的阅读记录'), findsOneWidget);
    expect(state.readingHistory.single.book.name, '保留漫画');
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('保留漫画'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('续读加载期间切换搜索词，晚到结果不会打开阅读器或写入目录缓存', (tester) async {
    final response = Completer<(Book, List<Chapter>)>();
    service.debugRuntimeOverride = (s) =>
        _HistoryRuntime(s, (_) => response.future);
    await record();
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.enterText(find.byType(TextField), '其他漫画');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的阅读记录'), findsOneWidget);
    response.complete((book, chapters));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    expect(state.detailCacheFor(book.bookUrl), isNull);
    expect(state.readingHistory, hasLength(1));
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('续读 历史漫画').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('从缓存续读按章节链接定位，早期插入章节不回退旧序号', (tester) async {
    await record();
    await state.saveDetailCache(book, [
      Chapter(title: '序章', url: '/intro'),
      ...chapters,
    ]);
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('历史漫画 · 第2话'), findsOneWidget);
    expect(
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).initialIndex,
      2,
    );
    expect(detailCalls, 0);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 2);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingHistoryScreen), findsOneWidget);
    expect(state.readingHistory.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无缓存时拉取目录后直接续读，进度和历史一起更新', (tester) async {
    await record(index: 2);
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pumpAndSettle();
    expect(detailCalls, 1);
    expect(find.text('历史漫画 · 第3话'), findsOneWidget);
    expect(state.detailCacheFor(book.bookUrl)?.chapters.length, 4);
    expect(state.readingHistory.single.chapter.url, chapters[2].url);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('加载期间移除历史会取消续读，晚到结果不打开阅读器或恢复记录', (tester) async {
    final response = Completer<(Book, List<Chapter>)>();
    service.debugRuntimeOverride = (s) =>
        _HistoryRuntime(s, (_) => response.future);
    await record();
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('移除 历史漫画 的阅读记录'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读记录'), findsOneWidget);
    response.complete((book, chapters));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    expect(state.readingHistory, isEmpty);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录加载失败保留历史，可通过详情恢复；来源停用也提供启用入口', (tester) async {
    service.debugRuntimeOverride = (s) =>
        _HistoryRuntime(s, (_) async => throw StateError('offline'));
    await record();
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法续读，可打开详情重试或换源'), findsOneWidget);
    expect(state.readingHistory.length, 1);
    await state.toggleSource(source.id);
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('漫画源已停用'), findsOneWidget);
    expect(find.text('启用「历史源」并重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号和键盘下可搜索、续读和移除，移除后保留书架', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    book.name = '很长的漫画名称与番外篇阅读记录';
    await state.toggleShelf(book);
    await record();
    await showHistory(tester, textScale: 2);
    await tester.enterText(find.byType(TextField), '番外篇');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('续读 ${book.name}'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('续读 ${book.name}').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('移除 ${book.name} 的阅读记录'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读记录'), findsOneWidget);
    expect(state.inShelf(book), isTrue);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书架菜单和设置页均可进入阅读历史', (tester) async {
    await record();
    await tester.pumpWidget(ComicForgeApp(state: state));
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读历史'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingHistoryScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读历史'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingHistoryScreen), findsOneWidget);
    expect(find.text('历史漫画'), findsOneWidget);
  });

  testWidgets('来源已移除时历史仍可直接续读已下载的话', (tester) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('comic-forge-history-offline-'),
    );
    addTearDown(() async {
      await directory!.delete(recursive: true);
    });
    final queue = DownloadQueue(
      sourceFor: (_) => null,
      store: DownloadStore(directory: () async => directory!),
      loadImages: (_, _) async => (
        urls: ['https://history.example/page.png'],
        headers: <String, String>{},
      ),
      fetchBytes: (_, _) async => downloadTestImage(),
    );
    state.dispose();
    state = AppState(downloadQueue: queue);
    await tester.runAsync(() async {
      await queue.enqueue(book, chapters, [3]);
      await queue.idle;
    });
    await record(index: 3);
    await showHistory(tester);
    await tester.tap(find.byTooltip('续读 历史漫画'));
    for (
      var i = 0;
      i < 50 && find.byType(ReaderNetworkImage).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('历史漫画 · 第4话'), findsOneWidget);
    expect(
      tester
          .widget<ReaderNetworkImage>(find.byType(ReaderNetworkImage))
          .imageUrl,
      startsWith('file:'),
    );
    expect(detailCalls, 0);
    expect(state.progressFor(book.bookUrl)?.chapterIndex, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
