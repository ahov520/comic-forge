import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';

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

const _page = '''
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

  group('AppState 滚动位置持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('保存→读取→load() 路径还原（跨重启记忆）', () async {
      final st = AppState();
      await st.saveScrollOffset('https://m.example.com/c/7', 1234.5);
      expect(st.scrollOffsetFor('https://m.example.com/c/7'), 1234.5);

      final st2 = AppState();
      await st2.load();
      expect(st2.scrollOffsetFor('https://m.example.com/c/7'), 1234.5);
    });

    test('LRU 上限 200：最旧被淘汰', () async {
      final st = AppState();
      await st.saveScrollOffset('old', 1);
      for (var i = 0; i < 200; i++) {
        await st.saveScrollOffset('k$i', i.toDouble());
      }
      expect(st.scrollOffsets.length, 200);
      expect(st.scrollOffsetFor('old'), isNull, reason: '最旧应被 LRU 淘汰');
      expect(st.scrollOffsetFor('k199'), 199);
    });
  });

  group('AppState 轻量自动体检', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('只探前 N 个（未探测优先）；7 天节流第二次跳过', () async {
      final st = AppState();
      for (var i = 0; i < 5; i++) {
        await st.addSourceManual(_src('s$i', 'h$i.example.com'));
      }
      var built = 0;
      final fetcher = FakeFetcher({
        'https://h0.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _page,
        'https://h1.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _page,
        'https://h2.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _page,
      });

      await st.autoProbeIfNeeded(
        maxSources: 3,
        interval: const Duration(days: 7),
        runtimeBuilder: (s) {
          built++;
          return SourceRuntime(source: s, fetcher: fetcher);
        },
      );
      expect(built, 3, reason: 'maxSources=3 应只探 3 个');
      final probed = st.sources.where((s) => s.lastOkAt > 0).length;
      expect(probed, 3);

      // 节流：interval 内不再执行
      await st.autoProbeIfNeeded(
        maxSources: 3,
        interval: const Duration(days: 7),
        runtimeBuilder: (s) {
          built++;
          return SourceRuntime(source: s, fetcher: fetcher);
        },
      );
      expect(built, 3, reason: '7 天内第二次调用应跳过');
    });

    test('节流过期后继续探测剩余未测源', () async {
      final st = AppState();
      for (var i = 0; i < 4; i++) {
        await st.addSourceManual(_src('s$i', 'h$i.example.com'));
      }
      final fetcher = FakeFetcher({
        'https://h3.example.com/search?q=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86': _page,
      });

      await st.autoProbeIfNeeded(
        maxSources: 2,
        interval: Duration.zero, // 立即过期
        runtimeBuilder: (s) => SourceRuntime(
            source: s,
            fetcher: FakeFetcher(const {})), // 前 2 个无路由 → 失败（lastOkAt 仍为 0）
      );
      // 排序按 lastOkAt 升序（未探测=0 优先），第二轮应探到未失败/未探测的
      await st.autoProbeIfNeeded(
        maxSources: 2,
        interval: Duration.zero,
        runtimeBuilder: (s) => SourceRuntime(source: s, fetcher: fetcher),
      );
      final probed = st.sources.where((s) => s.lastOkAt > 0).length;
      expect(probed, greaterThanOrEqualTo(1), reason: '后续轮次应覆盖未探测源');
    });
  });
}
