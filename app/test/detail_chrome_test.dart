import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book({
  String name = '海贼王',
  String author = '尾田荣一郎',
  String kind = '冒险/热血',
  String introduce = '伟大航道上的冒险。',
}) => Book(
  name: name,
  author: author,
  kind: kind,
  introduce: introduce,
  bookUrl: 'https://example.com/book/1',
);

ComicSource _src({
  String name = '社区源 A',
  String url = 'https://a.example.com',
}) => ComicSource.fromPpcatFlat({
  'bookSourceName': name,
  'bookSourceUrl': url,
  'ruleSearchUrl': '/s?q=searchKey',
});

void main() {
  test('splitKindTags 按中英分隔符拆标签并截断', () {
    expect(splitKindTags('冒险/热血，奇幻'), ['冒险', '热血', '奇幻']);
    expect(splitKindTags('a,b,c,d,e,f'), ['a', 'b', 'c', 'd', 'e']);
    expect(splitKindTags(''), isEmpty);
  });

  testWidgets('英雄区展示封面、作者、来源换源与开始阅读', (tester) async {
    var switched = false;
    var read = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailHero(
            book: _book(),
            sourceName: '社区源 A',
            switchCount: 3,
            onSwitchSource: () => switched = true,
            readLabel: '开始阅读',
            onRead: () => read = true,
          ),
        ),
      ),
    );

    expect(find.text('海贼王'), findsOneWidget);
    expect(find.text('尾田荣一郎'), findsOneWidget);
    expect(find.text('冒险'), findsOneWidget);
    expect(find.text('热血'), findsOneWidget);
    expect(find.text('伟大航道上的冒险。'), findsOneWidget);
    expect(find.text('展开简介'), findsNothing);
    expect(find.text('开始阅读'), findsOneWidget);
    expect(find.byType(BookCover), findsOneWidget);
    expect(find.byTooltip('换源：社区源 A'), findsOneWidget);

    await tester.tap(find.byTooltip('换源：社区源 A'));
    expect(switched, isTrue);
    await tester.tap(find.text('开始阅读'));
    expect(read, isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字号长简介可展开和收起，封面稳定且阅读按钮可操作：${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final introduction = List.filled(6, '少年和伙伴们踏上新的冒险，寻找传说中的岛屿。').join();
      var read = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailHero(
                book: _book(introduce: introduction),
                readLabel: '开始阅读',
                onRead: () => read = true,
              ),
            ),
          ),
        ),
      );
      final intro = find.text(introduction);
      final collapsedHeight = tester.getSize(intro).height;
      final coverHeight = tester.getSize(find.byType(BookCover)).height;
      await tester.ensureVisible(find.text('展开简介'));
      await tester.tap(find.text('展开简介'));
      await tester.pumpAndSettle();
      expect(tester.getSize(intro).height, greaterThan(collapsedHeight * 2));
      expect(tester.getSize(find.byType(BookCover)).height, coverHeight);
      expect(tester.widget<Text>(intro).maxLines, isNull);
      await tester.ensureVisible(find.text('开始阅读'));
      await tester.tap(find.text('开始阅读'));
      expect(read, isTrue);
      await tester.ensureVisible(find.text('收起简介'));
      await tester.tap(find.text('收起简介'));
      await tester.pumpAndSettle();
      expect(tester.getSize(intro).height, collapsedHeight);
      expect(find.text('展开简介'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('屏幕变窄导致三行预览溢出时才显示展开入口', (tester) async {
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final introduction = List.filled(80, '漫').join();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailHero(book: _book(introduce: introduction)),
          ),
        ),
      ),
    );
    expect(find.text('展开简介'), findsNothing);
    tester.view.physicalSize = const Size(320, 720);
    await tester.pumpAndSettle();
    expect(find.text('展开简介'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节行保留紧凑的 48px 点击区域并高亮当前话', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ChapterTile(
                index: 0,
                title: '第1话',
                isCurrent: false,
                onTap: () {},
              ),
              ChapterTile(
                index: 3,
                title: '第4话',
                isCurrent: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('第1话'), findsOneWidget);
    expect(find.text('第4话'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final tapArea = find.descendant(
      of: find.byType(ChapterTile).first,
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(tapArea).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.byType(ChapterTile).first).height,
      lessThanOrEqualTo(52),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterTile(
            index: 1043,
            title: '第1044话',
            isCurrent: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('1044'), findsOneWidget);
    expect(tester.getSize(find.text('1044')).height, lessThan(22));
  });

  testWidgets('换源面板加载骨架、空态 EmptyState、命中用 BookTile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    var picked = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwitchSourcePanel(
            bookName: '海贼王',
            snapshot: const AsyncSnapshot<List<(ComicSource, Book)>>.waiting(),
            state: state,
            onPick: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('换源 · 海贼王'), findsOneWidget);
    expect(find.byType(BookListSkeleton), findsOneWidget);
    final metadataRight = tester
        .getRect(
          find
              .byWidgetPredicate((w) => w is SkeletonBox && w.width == null)
              .first,
        )
        .right;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwitchSourcePanel(
            bookName: '海贼王',
            snapshot: const AsyncSnapshot<List<(ComicSource, Book)>>.withData(
              ConnectionState.done,
              [],
            ),
            state: state,
            onPick: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.text('其它源没有搜到同名书'), findsOneWidget);

    final hit = _book(name: '海贼王（源B）');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwitchSourcePanel(
            bookName: '海贼王',
            snapshot: AsyncSnapshot<List<(ComicSource, Book)>>.withData(
              ConnectionState.done,
              [(_src(name: '源B'), hit)],
            ),
            state: state,
            onPick: (_, book) => picked = book.name,
          ),
        ),
      ),
    );
    expect(find.byType(BookTile), findsOneWidget);
    expect(find.byTooltip('加入书架'), findsNothing);
    expect(find.byTooltip('来源：源B'), findsOneWidget);
    expect(
      tester
          .getRect(
            find
                .ancestor(
                  of: find.text(hit.name),
                  matching: find.byType(Column),
                )
                .first,
          )
          .right,
      metadataRight,
      reason: '换源骨架与实际卡片都不为收藏预留空白',
    );
    await tester.tap(find.text('海贼王（源B）'));
    expect(picked, '海贼王（源B）');
  });
}
