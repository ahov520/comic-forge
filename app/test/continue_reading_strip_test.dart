import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_sort.dart';
import 'package:comic_forge/ui/continue_reading_strip.dart';
import 'package:comic_forge/ui/reader_screen.dart';
import 'package:comic_forge/ui/reading_history_screen.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late Book serial;
  late Book done;
  late Book extra;
  late List<Chapter> chapters;
  late SourceService service;
  var detailCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    source = ComicSource.fromJson({
      'id': 'continue-ui',
      'name': '续读源',
      'url': 'https://continue.example',
      'rules': {'contentUrl': '.page@src'},
    });
    state = AppState();
    await state.addSourceManual(source);
    serial = Book(
      sourceId: source.id,
      name: '连载漫画',
      kind: '连载中',
      author: '甲',
      bookUrl: 'https://continue.example/serial',
    );
    done = Book(
      sourceId: source.id,
      name: '完结漫画',
      kind: '已完结',
      author: '乙',
      bookUrl: 'https://continue.example/done',
    );
    extra = Book(
      sourceId: source.id,
      name: '未收藏漫画',
      kind: '连载中',
      bookUrl: 'https://continue.example/extra',
    );
    chapters = List.generate(
      4,
      (i) => Chapter(
        title: '第${i + 1}话',
        url: 'https://continue.example/c${i + 1}',
      ),
    );
    service = SourceService.instance;
    service.debugClearSwitchCache();
    detailCalls = 0;
    service.debugRuntimeOverride = (source) =>
        _HistoryRuntime(source, (_) async {
          detailCalls++;
          return (serial, chapters);
        });
  });

  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  Future<void> record(Book book, {int index = 1}) => state.saveProgress(
    book,
    chapterUrl: chapters[index].url,
    chapterTitle: chapters[index].title,
    chapterIndex: index,
    chapterCount: chapters.length,
  );

  Future<void> showShelf(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder strip() => find.byKey(ContinueReadingStrip.stripKey);

  Finder stripText(String text) =>
      find.descendant(of: strip(), matching: find.text(text));

  Finder gridText(String text) =>
      find.descendant(of: find.byType(SliverGrid), matching: find.text(text));

  testWidgets('无阅读记录时不占位，空书架引导仍可用', (tester) async {
    await showShelf(tester);
    expect(find.text('继续阅读'), findsNothing);
    expect(strip(), findsNothing);
    expect(find.text('书架还没有漫画'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('最近阅读显示封面和章节进度，点按走现有续读', (tester) async {
    await state.toggleShelf(serial);
    await record(serial);
    await state.saveDetailCache(serial, chapters);
    await showShelf(tester);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(stripText(serial.name), findsOneWidget);
    expect(stripText('第2话 · 2/4'), findsOneWidget);
    expect(
      find.descendant(of: strip(), matching: find.byType(BookCover)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('续读 ${serial.name}'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('${serial.name} · 第2话'), findsOneWidget);
    expect(detailCalls, 0);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('未收藏漫画也可出现在继续阅读条并续读', (tester) async {
    service.debugRuntimeOverride = (s) => _HistoryRuntime(s, (_) async {
      detailCalls++;
      return (extra, chapters);
    });
    await record(extra, index: 2);
    await showShelf(tester);
    expect(find.text('书架还没有漫画'), findsOneWidget);
    expect(stripText(extra.name), findsOneWidget);
    expect(gridText(extra.name), findsNothing);
    await tester.tap(find.byTooltip('续读 ${extra.name}'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('${extra.name} · 第3话'), findsOneWidget);
    expect(detailCalls, 1);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('搜索、分组和连载筛选、排序只作用于书架网格', (tester) async {
    await state.toggleShelf(serial);
    await state.toggleShelf(done);
    final group = await state.shelfGroups.create('追更');
    await state.shelfGroups.assign(serial.bookUrl, [group]);
    await record(serial, index: 0);
    await record(done, index: 3);
    await showShelf(tester);
    expect(stripText(done.name), findsOneWidget);
    expect(stripText(serial.name), findsOneWidget);
    expect(
      tester.getTopLeft(stripText(done.name)).dx,
      lessThan(tester.getTopLeft(stripText(serial.name)).dx),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pumpAndSettle();
    expect(gridText(done.name), findsOneWidget);
    expect(gridText(serial.name), findsNothing);
    expect(stripText(serial.name), findsOneWidget);
    expect(stripText(done.name), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追更').last);
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有漫画'), findsOneWidget);
    expect(stripText(serial.name), findsOneWidget);
    expect(
      find.descendant(of: strip(), matching: find.byType(BookCover)),
      findsNWidgets(2),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '连载');
    await tester.pumpAndSettle();
    expect(gridText(serial.name), findsOneWidget);
    expect(gridText(done.name), findsNothing);
    expect(stripText(done.name), findsOneWidget);

    await tester.tap(find.byTooltip('排序：${state.shelfSort.label}'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<ShelfSort>, '书名'));
    await tester.pumpAndSettle();
    expect(state.shelfSort, ShelfSort.title);
    expect(stripText(done.name), findsOneWidget);
    expect(
      tester.getTopLeft(stripText(done.name)).dx,
      lessThan(tester.getTopLeft(stripText(serial.name)).dx),
    );
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('全部打开阅读历史；多选时隐藏继续阅读条', (tester) async {
    await state.toggleShelf(serial);
    await record(serial);
    await showShelf(tester);
    await tester.tap(find.byTooltip('查看全部阅读历史'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingHistoryScreen), findsOneWidget);
    expect(find.text(serial.name), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(strip(), findsOneWidget);

    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量管理'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0'), findsOneWidget);
    expect(find.text('继续阅读'), findsNothing);
    expect(strip(), findsNothing);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(strip(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
    '非 Android 不显示继续阅读条',
    (tester) async {
      await record(serial);
      await showShelf(tester);
      expect(find.text('继续阅读'), findsNothing);
      expect(strip(), findsNothing);
      expect(find.text('书架还没有漫画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('窄屏大字号下继续阅读条不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.toggleShelf(serial);
    await record(serial);
    await showShelf(tester, textScale: 2);
    expect(stripText(serial.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
