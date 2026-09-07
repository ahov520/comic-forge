import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  late Book book;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    book = Book(
      name: '海贼王',
      author: '尾田荣一郎',
      kind: '冒险',
      lastChapter: '第 1080 话',
      bookUrl: 'https://example.com/book/1',
    );
  });

  tearDown(() => state.dispose());

  testWidgets('手机宽度下信息按标题、作者标签、更新分层，收藏与封面居中', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [BookTile(book: book, state: state)],
          ),
        ),
      ),
    );
    final cover = tester.getRect(find.byType(BookCover));
    final favorite = tester.getRect(find.byType(IconButton));
    final title = tester.getRect(find.text(book.name));
    final metadata = tester.getRect(find.text('尾田荣一郎 · 冒险'));
    final chapter = tester.getRect(find.text('更新至 第 1080 话'));
    expect(favorite.center.dy, cover.center.dy);
    expect(favorite.width, greaterThanOrEqualTo(48));
    expect(favorite.height, greaterThanOrEqualTo(48));
    expect(title.bottom, lessThan(metadata.top));
    expect(metadata.bottom, lessThan(chapter.top));
    expect(title.right, lessThanOrEqualTo(favorite.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片分别展示元信息；收藏可即时切换且不会打开详情', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              BookTile(book: book, state: state, sourceLabel: '社区源 A'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('尾田荣一郎 · 冒险'), findsOneWidget);
    expect(find.text('更新至 第 1080 话'), findsOneWidget);
    expect(find.text('社区源 A'), findsOneWidget);

    await tester.tap(find.byTooltip('加入书架'));
    await tester.pumpAndSettle();
    expect(state.inShelf(book), isTrue);
    expect(find.byTooltip('移出书架'), findsOneWidget);
    expect(find.byType(BookDetailScreen), findsNothing);

    await tester.tap(find.byTooltip('移出书架'));
    await tester.pumpAndSettle();
    expect(state.inShelf(book), isFalse);
    expect(find.byTooltip('加入书架'), findsOneWidget);
    expect(find.byType(BookDetailScreen), findsNothing);
  });

  testWidgets('点击卡片仍可进入该书详情', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookTile(book: book, state: state),
        ),
      ),
    );
    await tester.tap(find.text('海贼王'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(
      tester.widget<BookDetailScreen>(find.byType(BookDetailScreen)).book,
      same(book),
    );
  });

  testWidgets('外部收藏变化即时同步，减少动态效果时直接切换图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [BookTile(book: book, state: state)],
          ),
        ),
      ),
    );

    await state.toggleShelf(book);
    await tester.pump();
    expect(find.byTooltip('移出书架'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await state.toggleShelf(book);
    await tester.pump();
    expect(find.byTooltip('加入书架'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字号长书名和来源不溢出：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      book.name = '很长的漫画书名包含特别篇和完整的番外故事';
      book.author = '很长的作者名称与联合创作团队';
      book.lastChapter = '第 1080 话：很长的最新章节标题';
      const source = '很长的社区漫画源名称与站点信息';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF169876),
              brightness: brightness,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                BookTile(book: book, state: state, sourceLabel: source),
              ],
            ),
          ),
        ),
      );
      expect(find.byTooltip('来源：$source'), findsOneWidget);
      await tester.tap(find.byTooltip('加入书架'));
      await tester.pumpAndSettle();
      expect(state.inShelf(book), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('空状态在低高度、大字号下可滚动到操作按钮', (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var acted = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: EmptyStateView(
            icon: Icons.search_off_outlined,
            title: '没有找到相关漫画',
            message: '试试更短的书名、作者名，或换一个关键词。',
            actionLabel: '修改关键词',
            onAction: () => acted = true,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('修改关键词'));
    await tester.tap(find.text('修改关键词'));
    expect(acted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
