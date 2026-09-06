import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/services/source_service.dart';

class FakeFetcher implements Fetcher {
  FakeFetcher(this.routes);
  final Map<String, String> routes;
  int hits = 0;

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
<html><body>
<div class="item"><a class="t" href="/c/1">同名书</a><span class="a">作者甲</span></div>
<div class="item"><a class="t" href="/c/2">别的书</a></div>
</body></html>
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

  test('scanSwitchTargets：同名优先命中 + 缓存共享飞行（二次不发请求）', () async {
    final svc = SourceService.instance;
    svc.debugClearSwitchCache();
    svc.debugRuntimeOverride = null;

    final current = _src('cur', 'cur.example.com');
    final others = [
      _src('b1', 'b1.example.com'),
      _src('b2', 'b2.example.com'),
    ];
    final fetcher = FakeFetcher({
      'https://b1.example.com/search?q=%E5%90%8C%E5%90%8D%E4%B9%A6': _page,
      'https://b2.example.com/search?q=%E5%90%8C%E5%90%8D%E4%B9%A6': _page,
    });
    // 注入 fetcher（b1/b2 运行时走它）
    final rts = <String, SourceRuntime>{};
    for (final s in [current, ...others]) {
      rts[s.id] = SourceRuntime(source: s, fetcher: fetcher);
    }
    // runtimeFor 的运行时来自 SourceService 单例——用 debugRuntimeFor 覆盖
    svc.debugRuntimeOverride = (s) => rts[s.id]!;

    final book =
        Book(name: '同名书', bookUrl: 'https://cur.example.com/b/1', sourceId: current.id);
    final all = [current, ...others];

    final r1 = await svc.scanSwitchTargets(book: book, allSources: all);
    expect(r1, hasLength(2), reason: '两个源都命中');
    expect(r1.first.$2.name, '同名书', reason: '同名优先');

    final hitsAfterFirst = fetcher.hits;
    final r2 = await svc.scanSwitchTargets(book: book, allSources: all);
    expect(r2, hasLength(2));
    expect(fetcher.hits, hitsAfterFirst, reason: '缓存命中不应再发请求');

    svc.debugRuntimeOverride = null;
    svc.debugClearSwitchCache();
    svc.debugRuntimeOverride = null;
  });
}
