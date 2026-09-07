import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 内置源快照（app/assets/store.json，493 条 ppcat 平铺规则）导入冒烟。
///
/// 背景：store.json 大量使用 `ruleSearchUrl` 平铺键；若映射缺失，
/// 导入后 rules.searchUrl 全空，搜索屏（只认 searchUrl 非空）会全灭。
void main() {
  final f = File('../app/assets/store.json');
  late List<ComicSource> sources;

  setUpAll(() {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    sources = (j['sources'] as List)
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat)
        .toList();
  });

  test('store.json 存在且规模正确', () {
    expect(f.existsSync(), isTrue);
    expect(sources.length, 493);
  });

  test('ruleSearchUrl 映射生效：searchUrl 覆盖率与 store.json 键一致', () {
    final withSearch = sources
        .where((s) => s.rules.searchUrl.isNotEmpty)
        .length;
    // 493 条中 484 条带 ruleSearchUrl（其余依赖 findUrl 或无搜索）
    expect(withSearch, 484, reason: 'searchUrl 非空应等于带 ruleSearchUrl 的条数');
  });

  test('配套规则字段批量导入生效', () {
    expect(sources.where((s) => s.rules.searchList.isNotEmpty).length, 493);
    expect(sources.where((s) => s.rules.searchBookUrl.isNotEmpty).length, 492);
    expect(sources.where((s) => s.rules.contentUrl.isNotEmpty).length, 492);
    expect(sources.where((s) => s.rules.chapterList.isNotEmpty).length, 491);
    expect(sources.where((s) => s.rules.findUrl.isNotEmpty).length, 488);
  });

  test('样例源（腾讯漫画）searchUrl 渲染出真实请求', () {
    final tx = sources.firstWhere((s) => s.url.contains('m.ac.qq.com'));
    expect(tx.name, '腾讯漫画（正版）');
    expect(tx.rules.searchUrl, contains('searchKey'));
    final rendered = renderUrlTemplate(tx.rules.searchUrl, {
      'key': Uri.encodeComponent('一人之下'),
      'keyword': Uri.encodeComponent('一人之下'),
      'searchKey': Uri.encodeComponent('一人之下'),
      'page': '2',
      'searchPage': '2',
      'pageSize': '20',
    });
    expect(rendered, startsWith('/search'));
    expect(rendered, contains('%E4%B8%80%E4%BA%BA%E4%B9%8B%E4%B8%8B'));
    expect(rendered, contains('page=2'));
    expect(rendered, isNot(contains('searchKey')));
  });

  test('headers 字典随导入生效（请求头不是空的）', () {
    final tx = sources.firstWhere((s) => s.url.contains('m.ac.qq.com'));
    expect(tx.headers['User-Agent'], 'Android');
    expect(sources.where((s) => s.headers.isNotEmpty).length, 180);
  });

  test('仓库导入入口解析完整 store，保留搜索规则与请求头', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/meta.json')) {
        return http.Response('{}', 200);
      }
      expect(request.url.path, endsWith('/store.json'));
      return http.Response.bytes(f.readAsBytesSync(), 200);
    });
    addTearDown(client.close);
    final bundle = await RepoClient(
      fetcher: HttpFetcher(client: client),
    ).subscribe('example/builtin-snapshot');
    expect(
      bundle.sources.map((s) => s.toJson()),
      sources.map((s) => s.toJson()),
    );
  });

  test('内置腾讯源真实规则经运行时生成请求并提取 HTML 搜索结果', () async {
    final tx = sources.firstWhere((s) => s.url == 'https://m.ac.qq.com');
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.host, 'm.ac.qq.com');
      expect(request.url.path, '/search/result');
      expect(request.url.queryParameters['word'], '一人之下');
      expect(request.url.queryParameters['page'], '2');
      expect(request.headers['User-Agent'], 'Android');
      return http.Response(
        '''
<div class="comic-item">
  <a class="comic-link" href="/comic/123">
    <span class="comic-title">一人之下</span>
  </a>
  <div class="comic-cover"><img src="/cover/123.jpg"></div>
  <span class="comic-tag">冒险</span>
  <span class="comic-update">第 10 话</span>
</div>
''',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final page = await SourceRuntime(
      source: tx,
      fetcher: HttpFetcher(client: client),
    ).search('一人之下', page: 2);
    final book = page.items.single;
    expect(book.name, '一人之下');
    expect(book.sourceId, tx.id);
    expect(book.bookUrl, 'https://m.ac.qq.com/comic/123');
    expect(book.coverUrl, 'https://m.ac.qq.com/cover/123.jpg');
    expect(book.kind, '冒险');
    expect(book.lastChapter, '第 10 话');
  });

  test('内置快看源真实规则经运行时分页并提取 JSON 搜索结果', () async {
    final kk = sources.firstWhere((s) => s.name == '快看漫画（正版）');
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/search/topic');
      expect(request.url.queryParameters['q'], '斗罗大陆');
      expect(request.url.queryParameters['since'], '48');
      return http.Response(
        jsonEncode({
          'data': {
            'hit': [
              {
                'id': 123,
                'title': '斗罗大陆',
                'user': {'nickname': '作者'},
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final page = await SourceRuntime(
      source: kk,
      fetcher: HttpFetcher(client: client),
    ).search('斗罗大陆', page: 2);
    expect(page.items.single.name, '斗罗大陆');
    expect(page.items.single.author, '作者');
    expect(
      page.items.single.bookUrl,
      'https://www.kuaikanmanhua.com/web/topic/123/',
    );
  });

  test('导入→持久化→重载（AppState 存取路径）规则不丢', () {
    var survived = 0;
    for (final s in sources) {
      final back = ComicSource.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      if (back.rules.searchUrl == s.rules.searchUrl &&
          back.rules.searchList == s.rules.searchList &&
          back.rules.contentUrl == s.rules.contentUrl) {
        survived++;
      }
    }
    expect(survived, 493, reason: '往返后规则必须逐条保真，否则二次启动搜索全灭');
  });
}
