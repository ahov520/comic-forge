import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';
import 'package:comic_forge/ui/widgets.dart';

void main() {
  testWidgets('SkeletonBox 渲染且持续脉冲（呼吸动画）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkeletonBox(width: 100, height: 40)),
      ),
    );
    expect(find.byType(SkeletonBox), findsOneWidget);
    final opacity0 = tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(SkeletonBox),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    await tester.pump(const Duration(milliseconds: 550));
    final opacity1 = tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(SkeletonBox),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity0, isNot(equals(opacity1)), reason: '呼吸脉冲应在推进');
  });

  testWidgets('减少动态效果时骨架停止脉冲，偏好变化后可恢复', (tester) async {
    final reduceMotion = ValueNotifier(true);
    addTearDown(reduceMotion.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: reduceMotion,
          builder: (context, disabled, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
            child: child!,
          ),
        ),
        home: const Scaffold(body: SkeletonBox(width: 100, height: 40)),
      ),
    );
    final fade = find.descendant(
      of: find.byType(SkeletonBox),
      matching: find.byType(FadeTransition),
    );
    double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
    final still = opacity();
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(), still);
    expect(tester.binding.hasScheduledFrame, isFalse);

    reduceMotion.value = false;
    await tester.pump();
    final before = opacity();
    await tester.pump(const Duration(milliseconds: 550));
    expect(opacity(), isNot(before));

    reduceMotion.value = true;
    await tester.pumpAndSettle();
    final stopped = opacity();
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(), stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final scale in [1.0, 2.0]) {
    for (final showShelfAction in [true, false]) {
      testWidgets('列表骨架与单行标题书卡的文字、封面位置一致：字号 $scale，收藏 $showShelfAction', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(340, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final state = AppState();
        addTearDown(state.dispose);
        final book = Book(name: '漫画', author: '作者', lastChapter: '1');
        Future<void> show(Widget child) => tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: child),
          ),
        );

        await show(BookListSkeleton(showShelfAction: showShelfAction));
        final boxes = find.byType(SkeletonBox);
        final cover = tester.getRect(boxes.at(0));
        final title = tester.getRect(boxes.at(1));
        final metadata = tester.getRect(boxes.at(2));
        final chapter = tester.getRect(boxes.at(3));
        final favorite = showShelfAction ? tester.getRect(boxes.at(4)) : null;
        final card = tester.getRect(find.byType(Card).first);

        await show(
          ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              BookTile(
                book: book,
                state: state,
                showShelfAction: showShelfAction,
              ),
            ],
          ),
        );
        expect(tester.getRect(find.byType(BookCover)), cover);
        expect(tester.getRect(find.byType(Card)), card);
        if (favorite != null) {
          expect(tester.getRect(find.byIcon(Icons.favorite_border)), favorite);
        }
        for (final pair in [
          (title, find.text('漫画')),
          (metadata, find.text('作者')),
          (chapter, find.text('更新至 1')),
        ]) {
          final text = tester.getRect(pair.$2);
          expect(text.topLeft, pair.$1.topLeft);
          expect(text.height, pair.$1.height);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('窄屏大字号详情骨架不溢出，加载完成后封面位置保持一致', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    addTearDown(st.dispose);
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '测试源',
      'bookSourceUrl': 'https://m.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);

    final book = Book(
      name: '很长的漫画书名包含特别篇',
      kind: '很长的分类标签用于测试窄屏/冒险/热血',
      bookUrl: 'https://m.example.com/b/1',
      sourceId: src.id,
    );
    final loader = Completer<(Book, List<Chapter>)>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: BookDetailScreen(
          book: book,
          appState: st,
          detailLoaderOverride: (_) => loader.future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DetailSkeleton), findsOneWidget);
    // 封面块 + 多个章节行骨架
    expect(
      find.byWidgetPredicate((w) => w is SkeletonBox && (w.height == 164)),
      findsOneWidget,
    );
    expect(find.byType(SkeletonBox).evaluate().length, greaterThan(6));
    final coverRect = tester.getRect(
      find.byWidgetPredicate((w) => w is SkeletonBox && w.height == 164),
    );
    expect(tester.takeException(), isNull);

    loader.complete((book, [Chapter(title: '第一话', url: '${book.bookUrl}/1')]));
    await tester.pumpAndSettle();
    expect(find.byType(DetailSkeleton), findsNothing);
    expect(tester.getRect(find.byType(BookCover)), coverRect);
    expect(tester.takeException(), isNull);
  });
}
