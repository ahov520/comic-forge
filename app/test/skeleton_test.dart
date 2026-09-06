import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';

void main() {
  testWidgets('SkeletonBox 渲染且持续脉冲（呼吸动画）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SkeletonBox(width: 100, height: 40)),
    ));
    expect(find.byType(SkeletonBox), findsOneWidget);
    final opacity0 = tester
        .widget<FadeTransition>(
            find.descendant(of: find.byType(SkeletonBox), matching: find.byType(FadeTransition)))
        .opacity
        .value;

    await tester.pump(const Duration(milliseconds: 550));
    final opacity1 = tester
        .widget<FadeTransition>(
            find.descendant(of: find.byType(SkeletonBox), matching: find.byType(FadeTransition)))
        .opacity
        .value;
    expect(opacity0, isNot(equals(opacity1)), reason: '呼吸脉冲应在推进');
  });

  testWidgets('书籍详情加载中显示骨架布局（封面块+章节行）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '测试源',
      'bookSourceUrl': 'https://m.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);

    // 详情 future 永不完成 → 停在加载态
    final loader = Completer<(Book, List<Chapter>)>();
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: Book(name: '书', bookUrl: 'https://m.example.com/b/1', sourceId: src.id),
        appState: st,
        detailLoaderOverride: (_) => loader.future,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DetailSkeleton), findsOneWidget);
    // 封面块 + 多个章节行骨架
    expect(find.byWidgetPredicate((w) =>
        w is SkeletonBox && (w.height == 150)), findsOneWidget);
    expect(find.byType(SkeletonBox).evaluate().length, greaterThan(6));
  });
}
