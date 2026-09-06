import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/source_update.dart';

/// 内存 FakeFetcher：URL → 文本（够 RepoClient 用）。
class FakeFetcher implements Fetcher {
  FakeFetcher(this.routes);
  final Map<String, String> routes;

  @override
  Future<String> getString(String url,
      {Map<String, String>? headers, String? charset}) async {
    final hit = routes[url];
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

ComicSource _src(String id, {String search = '/s?q=1'}) =>
    ComicSource.fromPpcatFlat({
      'bookSourceName': '源$id',
      'bookSourceUrl': 'https://m.example.com/$id',
      'ruleSearchUrl': search,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourceUpdate.merge', () {
    test('新源追加、规则变更更新且保留用户设置、未变跳过', () {
      final old1 = _src('a');
      old1.enabled = false;
      old1.failCount = 5;
      final existing = [old1, _src('b')];
      final incoming = [
        _src('a', search: '/s?q=2'), // 规则变了
        _src('b'), // 没变
        _src('c'), // 新增
      ];

      final r = SourceUpdate.merge(existing, incoming);
      expect(r.added, 1);
      expect(r.updated, 1);
      expect(r.sources.length, 3);

      final a = r.sources.firstWhere((s) => s.id.endsWith('/a'));
      expect(a.rules.searchUrl, '/s?q=2', reason: '更新应替换规则');
      expect(a.enabled, false, reason: '更新应保留用户启停');
      expect(a.failCount, 5, reason: '更新应保留健康记录');

      expect(r.sources.any((s) => s.id.endsWith('/c')), isTrue);
    });

    test('headers 变化也计为更新', () {
      final old1 = _src('a');
      final incoming = _src('a');
      incoming.headers['User-Agent'] = 'Android';
      final r = SourceUpdate.merge([old1], [incoming]);
      expect(r.updated, 1);
    });
  });

  group('AppState.refreshRepo', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('全流程：拉仓库→合并→lastRefresh 持久化；失败返回错误摘要', () async {
      const repo = 'https://github.com/u/r';
      final meta = jsonEncode({'ruleId': '1', 'ruleVersion': 2});
      final store = jsonEncode({
        'sources': [
          {'bookSourceName': '甲', 'bookSourceUrl': 'https://x.example.com/a', 'ruleSearchUrl': '/s?q=searchKey'},
          {'bookSourceName': '乙', 'bookSourceUrl': 'https://x.example.com/b', 'ruleSearchUrl': '/s?q=searchKey'},
        ]
      });
      final client = RepoClient(
        fetcher: FakeFetcher({
          'https://raw.githubusercontent.com/u/r/master/meta.json': meta,
          'https://raw.githubusercontent.com/u/r/master/store.json': store,
        }),
      );

      final st = AppState();
      await st.addRepoSubscribed(repo, const []);
      final r = await st.refreshRepo(repo, client: client);
      expect(r.ok, isTrue);
      expect(r.added, 2, reason: '两个新源应被加入');
      expect(r.total, 2);
      expect(st.sources.length, 2);
      expect(st.repoLastRefresh[repo], greaterThan(0));

      // 规则无变化的第二次刷新：0 新增 0 更新
      final r2 = await st.refreshRepo(repo, client: client);
      expect(r2.added, 0);
      expect(r2.updated, 0);

      // 网络失败 → 错误摘要而非异常
      final badClient = RepoClient(fetcher: FakeFetcher({}));
      final r3 = await st.refreshRepo(repo, client: badClient);
      expect(r3.ok, isFalse);
      expect(r3.error, isNotNull);
    });
  });
}
