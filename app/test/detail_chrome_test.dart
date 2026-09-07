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
}) =>
    Book(
      name: name,
      author: author,
      kind: kind,
      introduce: introduce,
      bookUrl: 'https://example.com/book/1',
    );

ComicSource _src({
  String name = '社区源 A',
  String url = 'https://a.example.com',
}) =>
    ComicSource.fromPpcatFlat({
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
    expect(find.text('开始阅读'), findsOneWidget);
    expect(find.byType(BookCover), findsOneWidget);
    expect(find.byTooltip('换源：社区源 A'), findsOneWidget);

    await tester.tap(find.byTooltip('换源：社区源 A'));
    expect(switched, isTrue);
    await tester.tap(find.text('开始阅读'));
    expect(read, isTrue);
  });

  testWidgets('当前章节行更紧凑并高亮书签', (tester) async {
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
    expect(
      tester.getSize(find.byType(ChapterTile).first).height,
      lessThan(48),
    );
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
    await tester.tap(find.text('海贼王（源B）'));
    expect(picked, '海贼王（源B）');
  });
}
