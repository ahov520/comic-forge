import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/book_detail_screen.dart';
import 'package:comic_forge/ui/widgets.dart';

/// 内存 FakeFetcher：URL → 文本。
class FakeFetcher implements Fetcher {
  FakeFetcher(this.routes);
  final Map<String, String> routes;

  @override
  Future<String> getString(String url,
      {Map<String, String>? headers, String? charset}) async {
    final hit = routes[url] ?? routes[url.split('?').first];
    if (hit == null) throw FetchException('no route for $url');
    return hit;
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async =>
      utf8.encode(await getString(url, headers: headers));

  @override
  Future<List<int>> send(SourceRequest request,
      {Map<String, String>? headers}) async {
    return utf8.encode(await getString(request.url, headers: request.headers));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('来源源被禁用：详情页提供一键启用并重试', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    final src = ComicSource.fromPpcatFlat({
      'bookSourceName': '被禁源',
      'bookSourceUrl': 'https://m.example.com',
      'ruleSearchUrl': '/s?q=searchKey',
    });
    await st.addSourceManual(src);
    await st.toggleSource(src.id); // 禁用（模拟体检自动禁用/手动关）
    expect(st.sources.first.enabled, isFalse);

    // 详情加载器（测试接缝）：启用后应被调用并返回数据
    var loaderCalls = 0;
    final book = Book(
        name: '书甲', bookUrl: 'https://m.example.com/b/1', sourceId: src.id);

    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: book,
        appState: st,
        detailLoaderOverride: (_) async {
          loaderCalls++;
          return (
            Book(name: '书甲详情', bookUrl: book.bookUrl, sourceId: src.id),
            <Chapter>[Chapter(title: '第1话', url: 'https://m.example.com/b/1/c1')],
          );
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 死路态：错误 + 「启用」按钮
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.textContaining('启用「被禁源」'), findsOneWidget);

    // 点启用 → 源被启用 → 详情重新加载成功
    await tester.tap(find.textContaining('启用「被禁源」'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(st.sources.first.enabled, isTrue, reason: '一键启用应翻转开关');
    expect(loaderCalls, greaterThanOrEqualTo(1), reason: '启用后应重新加载详情');
    expect(find.text('第1话'), findsOneWidget, reason: '章节列表应加载出来');
  });

  testWidgets('来源源被移除：只显示通用错误与重试（无启用按钮）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState();
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        book: Book(name: '书乙', bookUrl: 'https://gone.example.com/b/2', sourceId: 'nope'),
        appState: st,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.textContaining('启用「'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });
}
