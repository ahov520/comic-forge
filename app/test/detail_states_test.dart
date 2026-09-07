import 'dart:async';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/detail_chrome.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });

  tearDown(() => state.dispose());

  for (final brightness in Brightness.values) {
    testWidgets('窄屏离线目录与收藏状态正常更新：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = ComicSource.fromPpcatFlat({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'https://example.com',
      });
      await state.addSourceManual(source);
      final book = Book(
        name: '漫画',
        bookUrl: 'https://example.com/book/1',
        sourceId: source.id,
      );
      await state.saveDetailCache(
        book,
        List.generate(
          1004,
          (i) => Chapter(title: '第 $i 话', url: '${book.bookUrl}/$i'),
        ),
      );
      final refresh = Completer<(Book, List<Chapter>)>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BookDetailScreen(
            book: book,
            appState: state,
            detailLoaderOverride: (_) => refresh.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('离线目录'));
      expect(find.text('章节 (1004)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('加入书架'));
      await tester.pumpAndSettle();
      expect(state.inShelf(book), isTrue);
      expect(find.byTooltip('移出书架'), findsOneWidget);

      await state.toggleShelf(book);
      await tester.pumpAndSettle();
      expect(find.byTooltip('加入书架'), findsOneWidget);
    });
  }

  testWidgets('空目录可重新加载，返回章节后恢复阅读入口', (tester) async {
    final source = ComicSource.fromPpcatFlat({
      'bookSourceName': '测试源',
      'bookSourceUrl': 'https://example.com',
    });
    await state.addSourceManual(source);
    final book = Book(
      name: '测试漫画',
      bookUrl: 'https://example.com/book/1',
      sourceId: source.id,
    );
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          book: book,
          appState: state,
          detailLoaderOverride: (_) async => (
            book,
            ++loads == 1
                ? <Chapter>[]
                : [Chapter(title: '第一话', url: '${book.bookUrl}/1')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无章节'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
    await tester.ensureVisible(find.text('重新加载'));
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('暂无章节'), findsNothing);
    expect(find.text('第一话'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误态在低高度、大字号下可滚动到恢复与重试按钮', (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var enabled = false;
    var retried = false;
    const action = '启用「很长的社区漫画来源名称」并重试';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ErrorView(
            title: '漫画源已停用',
            message: '启用来源后，即可重新加载这本漫画。',
            actionLabel: action,
            onAction: () => enabled = true,
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text(action));
    await tester.tap(find.text(action));
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));

    expect(enabled, isTrue);
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('换源失败结束骨架加载，长书名在窄屏大字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SwitchSourcePanel(
            bookName: '很长的漫画书名包含特别篇和完整的番外故事',
            snapshot: AsyncSnapshot<List<(ComicSource, Book)>>.withError(
              ConnectionState.done,
              StateError('offline'),
            ),
            state: state,
            onPick: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookListSkeleton), findsNothing);
    expect(find.text('暂时无法查找其它来源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
