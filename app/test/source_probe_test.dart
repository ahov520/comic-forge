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

    test('并发受限也能全部完成；禁用源不参与体检', () async {
      final st = AppState();
      final good = _src('g1', 'ok1.example.com');
      final disabled = _src('off', 'off.example.com');
      disabled.enabled = false;
      await st.addSourceManual(good);
      await st.addSourceManual(disabled);

      final fetcher = FakeFetcher({
        'https://ok1.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _searchPage,
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
