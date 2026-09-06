import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/skeleton.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SWR 缓存命中：首帧直出缓存内容，不闪骨架', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '缓存源',
      'bookSourceUrl': 'https://m.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);
    // 预置离线目录缓存（上次会话拉取过）
    await st.saveDetailCache(
      Book(name: '缓存书名', bookUrl: 'https://m.example.com/b/1', sourceId: src.id),
      [
        Chapter(title: '第1话', url: 'https://m.example.com/b/1/c1'),
        Chapter(title: '第2话', url: 'https://m.example.com/b/1/c2'),
      ],
    );

    // 后台刷新永不完成（模拟弱网）→ 内容应始终为缓存版本
    final never = Completer<(Book, List<Chapter>)>();
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: Book(name: '缓存书名', bookUrl: 'https://m.example.com/b/1', sourceId: src.id),
        appState: st,
        detailLoaderOverride: (_) => never.future,
      ),
    ));
    await tester.pump(); // 首帧
    await tester.pump(const Duration(milliseconds: 50));

    // 首帧即直出缓存内容
    expect(find.text('第1话'), findsOneWidget);
    expect(find.text('第2话'), findsOneWidget);
    // 不闪骨架（真实网络正常时也不应出现）
    expect(find.byType(DetailSkeleton), findsNothing);
  });

  testWidgets('无缓存：显示骨架直至加载完成', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '裸源',
      'bookSourceUrl': 'https://n.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);

    final loader = Completer<(Book, List<Chapter>)>();
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: Book(name: '无缓存书', bookUrl: 'https://n.example.com/b/9', sourceId: src.id),
        appState: st,
        detailLoaderOverride: (_) => loader.future,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(DetailSkeleton), findsOneWidget, reason: '无缓存应显示骨架');

    loader.complete((
      Book(name: '加载完成书', bookUrl: 'https://n.example.com/b/9', sourceId: src.id),
      [Chapter(title: '章节甲', url: 'https://n.example.com/b/9/c1')],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(DetailSkeleton), findsNothing);
    expect(find.text('章节甲'), findsOneWidget);
  });
}
