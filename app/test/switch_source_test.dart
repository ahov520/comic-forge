import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('换源进度迁移：按章序号写入新书进度（截断保护）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final srcA = ComicSource.fromPpcatFlat({
      'bookSourceName': '源A',
      'bookSourceUrl': 'https://a.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    final srcB = ComicSource.fromPpcatFlat({
      'bookSourceName': '源B',
      'bookSourceUrl': 'https://b.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(srcA);
    await st.addSourceManual(srcB);

    // 旧书：读到第 4 话（index 3）
    final oldBook = Book(name: '同书', bookUrl: 'https://a.example.com/b/1', sourceId: srcA.id);
    await st.saveProgress(oldBook,
        chapterUrl: 'https://a.example.com/b/1/c4',
        chapterTitle: '第4话',
        chapterIndex: 3,
        chapterCount: 10);

    // 新源书只有 3 话 → carry index 3 应截断为 2
    final newBook = Book(name: '同书', bookUrl: 'https://b.example.com/b/9', sourceId: srcB.id);
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: newBook,
        appState: st,
        carryChapterIndex: 3,
        detailLoaderOverride: (_) async => (
          Book(name: '同书', bookUrl: newBook.bookUrl, sourceId: srcB.id),
          [
            Chapter(title: '新01', url: 'https://b.example.com/c1'),
            Chapter(title: '新02', url: 'https://b.example.com/c2'),
            Chapter(title: '新03', url: 'https://b.example.com/c3'),
          ],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final p = st.progressFor(newBook.bookUrl);
    expect(p, isNotNull, reason: '换源后新书应迁移到进度');
    expect(p!.chapterIndex, 2, reason: 'carry 3 截断到新章节范围末位');
    expect(p.chapterTitle, '新03');
    // 旧书进度不被破坏
    expect(st.progressFor(oldBook.bookUrl)!.chapterIndex, 3);
    // 「续读」按钮应出现（高亮该章）
    expect(find.textContaining('续读'), findsOneWidget);
  });

  testWidgets('无 carry 时不写新书进度', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '源C',
      'bookSourceUrl': 'https://c.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);
    final nb = Book(name: '另一书', bookUrl: 'https://c.example.com/b/5', sourceId: src.id);
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: nb,
        appState: st,
        detailLoaderOverride: (_) async => (
          Book(name: '另一书', bookUrl: nb.bookUrl, sourceId: src.id),
          [Chapter(title: '01', url: 'https://c.example.com/c1')],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(st.progressFor(nb.bookUrl), isNull, reason: '普通打开不产生进度');
  });
}
