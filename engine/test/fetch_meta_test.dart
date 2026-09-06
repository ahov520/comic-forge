import 'dart:convert';

import 'package:engine/src/net/fetcher.dart';
import 'package:engine/src/net/request.dart';
import 'package:engine/src/store/repo_client.dart';
import 'package:test/test.dart';

class _FakeFetcher implements Fetcher {
  _FakeFetcher(this.routes);
  final Map<String, String> routes;

  @override
  Future<String> getString(String url, {Map<String, String>? headers, String? charset}) async {
    final hit = routes[url];
    if (hit == null) throw FetchException('no route for $url');
    return hit;
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async =>
      utf8.encode(await getString(url, headers: headers));

  @override
  Future<List<int>> send(SourceRequest request, {Map<String, String>? headers}) async =>
      utf8.encode(await getString(request.url, headers: request.headers));
}

void main() {
  test('fetchMeta 只拉 meta：版本号与 auto 语义正确', () async {
    final client = RepoClient(fetcher: _FakeFetcher({
      'https://raw.githubusercontent.com/u/r/master/meta.json':
          '{"ruleId":"1","ruleVersion":42,"ruleAuto":true}',
    }));
    final meta = await client.fetchMeta('https://github.com/u/r');
    expect(meta.ruleVersion, 42);
    expect(meta.ruleAuto, isTrue);
  });

  test('fetchMeta：仓库无 meta 返回默认值 0（不抛错）', () async {
    final client = RepoClient(fetcher: _FakeFetcher({}));
    final meta = await client.fetchMeta('github.com/u/r');
    expect(meta.ruleVersion, 0);
  });

  test('fetchMeta：坏地址抛 FormatException', () async {
    final client = RepoClient(fetcher: _FakeFetcher({}));
    expect(() => client.fetchMeta('https://example.com/foo'), throwsFormatException);
  });
}
