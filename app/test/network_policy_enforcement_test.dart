import 'dart:io';

import 'package:comic_forge/services/download_store.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/download_queue.dart';
import 'package:comic_forge/ui/reader_network_image.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_test_image.dart';
import 'support/fake_fetcher.dart';

ComicSource _source(String id, String host) => ComicSource.fromJson({
  'id': id,
  'name': '源$id',
  'url': 'https://$host',
  'rules': {
    'searchUrl': '/search?q=searchKey',
    'searchList': '.book',
    'searchName': 'a@text',
    'searchBookUrl': 'a@href',
  },
});

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SourceService.instance.debugResetNetworkPolicy();
    SourceService.instance.debugClearSwitchCache();
    state = AppState();
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    SourceService.instance.debugResetNetworkPolicy();
    state.dispose();
  });

  testWidgets('搜索拦截被屏蔽主机，不计入源健康失败', (tester) async {
    await state.addSourceManual(_source('ok', 'ok.example'));
    await state.addSourceManual(_source('bad', 'blocked.example'));
    await state.addBlockedDomain('blocked.example');
    final inner = FakeFetcher(
      (uri) => '<div class="book"><a href="/book">可见结果</a></div>',
    );
    SourceService.instance.debugRuntimeOverride = (source) => SourceRuntime(
      source: source,
      fetcher: PolicyFetcher(
        inner: inner,
        policy: SourceService.instance.networkPolicy,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: SearchScreen(state: state)));
    await tester.enterText(find.byType(TextField), '测试漫画');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(inner.requests.map((r) => r.host), ['ok.example']);
    expect(find.text('可见结果'), findsOneWidget);
    expect(find.text('已聚合 2 个源 · 1 成功 1 屏蔽'), findsOneWidget);
    expect(state.sources.firstWhere((s) => s.id == 'bad').failCount, 0);

    await tester.tap(find.byTooltip('查看失败源'));
    await tester.pumpAndSettle();
    expect(find.text('域名已屏蔽'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阅读器拦截网络图，本地 file 图不受黑名单影响', (tester) async {
    final policy = NetworkPolicy(domains: ['blocked.example']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderNetworkImage(
            imageUrl: 'https://cdn.blocked.example/page.png',
            pageNumber: 3,
            headers: const {},
            policy: policy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 3 张图片域名已被屏蔽'), findsOneWidget);
    expect(find.textContaining('blocked.example'), findsWidgets);

    final file = File('${Directory.systemTemp.path}/cf-offline-page.png')
      ..writeAsBytesSync(downloadTestImage());
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderNetworkImage(
            imageUrl: file.uri.toString(),
            pageNumber: 1,
            headers: const {},
            policy: policy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已被屏蔽'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('下载命中黑名单给出可读原因，已完成离线包仍可读取', () async {
    final directory = await Directory.systemTemp.createTemp(
      'comic-forge-blocklist-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final book = Book(
      sourceId: 'dl',
      name: '离线',
      bookUrl: 'https://blocked.example/book',
    );
    final chapter = Chapter(title: '第一话', url: 'https://blocked.example/c1');
    final store = DownloadStore(directory: () async => directory);
    final ok = DownloadQueue(
      sourceFor: (_) => null,
      store: store,
      loadImages: (_, _) async =>
          (
            urls: ['https://blocked.example/1.png'],
            headers: const <String, String>{},
          ),
      fetchBytes: (_, _) async => downloadTestImage(),
    );
    addTearDown(ok.dispose);
    await ok.enqueue(book, [chapter], [0]);
    await ok.idle;
    expect(ok.tasks.single.status, DownloadStatus.completed);
    await state.addBlockedDomain('blocked.example');
    final offline = await ok.offlineImages(book, chapter);
    expect(offline, isNotNull);
    expect(offline!.single, startsWith('file:'));

    final blocked = DownloadQueue(
      sourceFor: (_) => null,
      store: store,
      loadImages: (_, _) async =>
          (
            urls: ['https://blocked.example/2.png'],
            headers: const <String, String>{},
          ),
      fetchBytes: (url, headers) =>
          SourceService.instance.fetcher.getBytes(url, headers: headers),
    );
    addTearDown(blocked.dispose);
    await blocked.enqueue(
      Book(
        sourceId: 'dl2',
        name: '在线',
        bookUrl: 'https://blocked.example/book2',
      ),
      [Chapter(title: '第二话', url: 'https://blocked.example/c2')],
      [0],
    );
    await blocked.idle;
    final failed = blocked.tasks.where((t) => t.chapter.url.endsWith('/c2'));
    expect(failed, hasLength(1));
    expect(failed.single.status, DownloadStatus.failed);
    expect(failed.single.error, '域名已被屏蔽：blocked.example');
  });
}
