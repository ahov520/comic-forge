import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final (input, canonical) in [
    ('github.com/AcgLibrary/ppcat_store', 'github.com/AcgLibrary/ppcat_store'),
    ('gitee.com/team/comics', 'gitee.com/team/comics'),
    ('www.github.com/team/comics', 'github.com/team/comics'),
    ('www.gitee.com/team/comics', 'gitee.com/team/comics'),
    ('  HTTPS://WWW.GITHUB.COM/Team/Comics.git/  ', 'github.com/Team/Comics'),
    ('https://gitee.com/team/comics.git?from=share', 'gitee.com/team/comics'),
    ('AcgLibrary/ppcat_store', 'github.com/AcgLibrary/ppcat_store'),
    ('AcgLibrary/ppcat_store.git/', 'github.com/AcgLibrary/ppcat_store'),
    ('https://github.com/team/comics/tree/main', 'github.com/team/comics'),
  ]) {
    test('仓库地址归一：$input', () {
      expect(RepoRef.parse(input)?.canonical, canonical);
    });
  }

  for (final input in [
    '',
    'github.com/team',
    'gitee.com/team',
    'example.com/team/comics',
    'team/comics extra',
    'ftp://example.com/store.json',
    '仓库 https://github.com/team/comics',
    'https://github.com/team/.git',
    'https://github.com/team/%FF',
    'https://user:secret@example.com/store.json',
  ]) {
    test('不完整或错误的仓库地址不被识别为其它仓库：$input', () {
      expect(RepoRef.parse(input), isNull);
    });
  }

  for (final (input, canonical) in [
    (
      'https://cdn.example.com/rules/store.json',
      'https://cdn.example.com/rules/store.json',
    ),
    (
      '  HTTP://CDN.EXAMPLE.COM/store.json#frag  ',
      'http://cdn.example.com/store.json',
    ),
    (
      'https://raw.githubusercontent.com/u/r/master/store.json',
      'https://raw.githubusercontent.com/u/r/master/store.json',
    ),
  ]) {
    test('远程源列表 URL 归一：$input', () {
      final ref = RepoRef.parse(input);
      expect(ref, isNotNull);
      expect(ref!.isListUrl, isTrue);
      expect(ref.canonical, canonical);
    });
  }

  for (final (input, root) in [
    (
      'github.com/AcgLibrary/ppcat_store',
      'https://raw.githubusercontent.com/AcgLibrary/ppcat_store/master',
    ),
    ('gitee.com/team/comics', 'https://gitee.com/team/comics/raw/master'),
  ]) {
    test('按无协议地址订阅会读取正确仓库并导入源：$input', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        final url = request.url.toString();
        requests.add(url);
        if (url == '$root/meta.json') {
          return http.Response('{"ruleVersion":7}', 200);
        }
        if (url == '$root/store.json') {
          return http.Response(
            jsonEncode([
              {
                'id': 'comic-source',
                'name': '漫画源',
                'url': 'https://comic.example',
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      });
      addTearDown(client.close);
      final bundle = await RepoClient(
        fetcher: HttpFetcher(client: client),
      ).subscribe(input);
      expect(bundle.ref.canonical, input);
      expect(bundle.meta.ruleVersion, 7);
      expect(bundle.sources.single.id, 'comic-source');
      expect(requests, ['$root/meta.json', '$root/store.json']);
    });
  }

  test('按源列表 URL 订阅只拉取该地址，解析明文 store', () async {
    const listUrl = 'https://cdn.example.com/rules/store.json';
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.toString());
      expect(request.url.toString(), listUrl);
      return http.Response(
        jsonEncode({
          'sources': [
            {
              'id': 'list-source',
              'name': '列表源',
              'url': 'https://comic.example',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final bundle = await RepoClient(
      fetcher: HttpFetcher(client: client),
    ).subscribe(listUrl);
    expect(bundle.ref.isListUrl, isTrue);
    expect(bundle.ref.canonical, listUrl);
    expect(bundle.track, 'A');
    expect(bundle.sources.single.id, 'list-source');
    expect(requests, [listUrl]);
  });

  test('源列表 URL 不是明文 JSON 时给出明确错误', () async {
    final client = MockClient(
      (request) async => http.Response('<html></html>', 200),
    );
    addTearDown(client.close);
    expect(
      () => RepoClient(
        fetcher: HttpFetcher(client: client),
      ).subscribe('https://cdn.example.com/rules/store.json'),
      throwsA(isA<FetchException>()),
    );
  });
}
