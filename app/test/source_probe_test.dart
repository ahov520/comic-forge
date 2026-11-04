import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';

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
    return utf8
        .encode(await getString(request.url, headers: request.headers));
  }
}

const _searchPage = '''
<html><body><div class="item"><a class="t" href="/c/1">书甲</a></div></body></html>
''';

ComicSource _src(String id, String host) => ComicSource.fromPpcatFlat({
      'bookSourceName': '源$id',
      'bookSourceUrl': 'https://$host',
      'ruleSearchUrl': '/search?q=searchKey',
      'ruleSearchList': 'class.item',
      'ruleSearchName': 'class.t@text',
      'ruleSearchNoteUrl': 'class.t@href',
      'ruleChapterList': '.chapters a',
      'ruleChapterName': 'text',
      'ruleContentUrl': 'href',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState.probeSources 健康体检', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('好源清零计数、坏源累加并记录原因，进度回调逐个推进', () async {
      final st = AppState();
      final good = _src('good', 'good.example.com');
      final bad = _src('bad', 'bad.example.net');
      await st.addSourceManual(good);
      await st.addSourceManual(bad);
      // 预置坏源已有失败记录（体检成功应清零）
      await st.reportSourceHealth(const [], {good.id: '旧错误'});

      final fetcher = FakeFetcher({
        'https://good.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _searchPage,
        'https://good.example.com/c/1':
            '<div class="chapters"><a href="/read/1">第1话</a></div>',
        // bad 域名无路由 → 失败
      });
      SourceRuntime rt(ComicSource s) =>
          SourceRuntime(source: s, fetcher: fetcher);

      final progress = <int>[];
      final (ok, total) = await st.probeSources(
        keyword: '斗罗大陆',
        concurrency: 4,
        timeout: const Duration(seconds: 3),
        runtimeBuilder: rt,
        onProgress: (d, t) => progress.add(d),
      );

      expect(total, 2);
      expect(ok, 1);
      expect(progress.last, 2, reason: '进度最终到达 total');
      expect(progress.first, greaterThanOrEqualTo(1));

      final g = st.sources.firstWhere((s) => s.id == good.id);
      expect(g.failCount, 0, reason: '体检成功应清零失败计数');
      expect(g.lastOkAt, greaterThan(0));
      final b = st.sources.firstWhere((s) => s.id == bad.id);
      expect(b.failCount, 1, reason: '体检失败应累加');
      expect(b.lastError, isNotEmpty);
    });

    test('搜索为空是待确认，不增加失效次数', () async {
      final state = AppState();
      addTearDown(state.dispose);
      final source = _src('empty', 'empty.example.com');
      await state.addSourceManual(source);
      final fetcher = FakeFetcher({
        'https://empty.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86':
            '<html><body>没有结果</body></html>',
      });
      final (ok, total) = await state.probeSources(
        runtimeBuilder: (s) => SourceRuntime(source: s, fetcher: fetcher),
      );
      expect((ok, total), (0, 1));
      expect(source.lastCheckStatus, 'unknown');
      expect(source.failCount, 0);
      expect(source.lastCheckedAt, greaterThan(0));
    });

    test('搜索成功但目录为空，必须判为异常源', () async {
      final state = AppState();
      addTearDown(state.dispose);
      final source = _src('nocatalog', 'nocatalog.example.com');
      await state.addSourceManual(source);
      final fetcher = FakeFetcher({
        'https://nocatalog.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86':
            _searchPage,
        'https://nocatalog.example.com/c/1': '<div>暂无目录</div>',
      });
      final (ok, total) = await state.probeSources(
        runtimeBuilder: (s) => SourceRuntime(source: s, fetcher: fetcher),
      );
      expect((ok, total), (0, 1));
      expect(source.lastCheckStatus, 'broken');
      expect(source.lastCheckNote, contains('目录为空'));
      expect(source.failCount, 1);
    });

    test('自动体检在不同启动周期轮换源，不重复卡在第一个源', () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.addSourceManual(_src('a', 'first.example'));
      await state.addSourceManual(_src('b', 'second.example'));
      final fake = FakeFetcher(const {});
      SourceRuntime build(ComicSource s) =>
          SourceRuntime(source: s, fetcher: fake);
      await state.autoProbeIfNeeded(
        maxSources: 1,
        interval: Duration.zero,
        runtimeBuilder: build,
      );
      expect(state.sources.where((s) => s.lastCheckedAt > 0).length, 1);
      await state.autoProbeIfNeeded(
        maxSources: 1,
        interval: Duration.zero,
        runtimeBuilder: build,
      );
      expect(state.sources.where((s) => s.lastCheckedAt > 0).length, 2);
    });

    test('并发受限也能全部完成；禁用源不参与体检', () async {
      final st = AppState();
      final good = _src('g1', 'ok1.example.com');
      final disabled = _src('off', 'off.example.com');
      disabled.enabled = false;
      await st.addSourceManual(good);
      await st.addSourceManual(disabled);

      final fetcher = FakeFetcher({
        'https://ok1.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _searchPage,
        'https://ok1.example.com/c/1':
            '<div class="chapters"><a href="/read/1">第1话</a></div>',
      });
      var built = 0;
      final (ok, total) = await st.probeSources(
        concurrency: 1,
        timeout: const Duration(seconds: 3),
        runtimeBuilder: (s) {
          built++;
          return SourceRuntime(source: s, fetcher: fetcher);
        },
      );
      expect((ok, total), (1, 1), reason: '禁用源不计入');
      expect(built, 1);
    });
  });
}
