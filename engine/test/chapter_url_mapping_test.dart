import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final loader in {
    'fromPpcatFlat': ComicSource.fromPpcatFlat,
    'fromJson': ComicSource.fromJson,
  }.entries) {
    group(loader.key, () {
      test('双字段章节链接优先使用 ruleContentUrl，与 JSON 键顺序无关', () {
        final fields = {
          'ruleContentUrl': 'tag.a@href',
          'ruleChapterUrl': 'id.btn_expandChapterList@href',
          'ruleBookContent': 'img.pic@src',
        };
        for (final entries in [
          fields.entries,
          fields.entries.toList().reversed,
        ]) {
          final source = loader.value(
            Map<String, dynamic>.fromEntries(entries),
          );
          expect(source.rules.chapterUrl, 'tag.a@href');
          expect(source.rules.contentUrl, 'img.pic@src');
        }
      });

      test('ruleContentUrl 缺省、为空或类型错误时回填 ruleChapterUrl', () {
        for (final fields in <Map<String, dynamic>>[
          {},
          {'ruleContentUrl': ''},
          {'ruleContentUrl': null},
          {'ruleContentUrl': 42},
        ]) {
          final source = loader.value({
            ...fields,
            'ruleChapterUrl': 'tag.a@href',
          });
          expect(source.rules.chapterUrl, 'tag.a@href', reason: '$fields');
        }
      });

      test('无有效章节链接规则时保持为空', () {
        for (final fields in <Map<String, dynamic>>[
          {},
          {'ruleContentUrl': '', 'ruleChapterUrl': ''},
          {'ruleContentUrl': null, 'ruleChapterUrl': null},
          {'ruleContentUrl': 42, 'ruleChapterUrl': 42},
        ]) {
          expect(loader.value(fields).rules.chapterUrl, isEmpty);
        }
      });
    });
  }

  test('fromJson 的 ruleChapterUrl 回填不覆盖已有嵌套章节链接', () {
    final source = ComicSource.fromJson({
      'rules': {'chapterUrl': 'a.saved@href'},
      'ruleContentUrl': '',
      'ruleChapterUrl': 'id.btn_expandChapterList@href',
    });
    expect(source.rules.chapterUrl, 'a.saved@href');

    final empty = ComicSource.fromJson({
      'rules': {'chapterUrl': ''},
      'ruleChapterUrl': 'tag.a@href',
    });
    expect(empty.rules.chapterUrl, 'tag.a@href');
  });

  test('腾讯快照双字段导入和持久化保留完整章节链接规则', () {
    final snapshot =
        jsonDecode(File('../app/assets/store.json').readAsStringSync())
            as Map<String, dynamic>;
    final sources = (snapshot['sources'] as List).cast<Map<String, dynamic>>();
    final tencent = sources.singleWhere(
      (source) => source['bookSourceUrl'] == 'https://m.ac.qq.com',
    );
    const chapterUrl =
        r'tag.a@href#.*?/chapter/index/id/(\d+)/cid/(\d+)#https://ac.qq.com/ComicView/index/id/$1/cid/$2';
    expect(tencent['ruleContentUrl'], chapterUrl);
    expect(tencent['ruleChapterUrl'], 'id.btn_expandChapterList@href');

    final imported = ComicSource.fromPpcatFlat(tencent);
    expect(imported.rules.chapterUrl, chapterUrl);
    final restored = ComicSource.fromJson(
      jsonDecode(jsonEncode(imported.toJson())) as Map<String, dynamic>,
    );
    expect(restored.rules.chapterUrl, chapterUrl);

    final dualFields = sources.where(
      (source) =>
          source['ruleContentUrl'] is String &&
          (source['ruleContentUrl'] as String).isNotEmpty &&
          source['ruleChapterUrl'] is String &&
          (source['ruleChapterUrl'] as String).isNotEmpty,
    );
    expect(dualFields, isNotEmpty);
    for (final fields in dualFields) {
      expect(
        ComicSource.fromPpcatFlat(fields).rules.chapterUrl,
        fields['ruleContentUrl'],
        reason: fields['bookSourceName'] as String?,
      );
    }
  });

  test('双字段源通过章节链接加载目录和图片', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      final body = switch (request.url.path) {
        '/comic/1' =>
          '''
<a id="btn_expandChapterList" href="/comic/1/catalog">展开目录</a>
<ul class="chapters">
  <li><a href="/chapter/1">第1话</a></li>
  <li><a href="/chapter/2">第2话</a></li>
</ul>
''',
        '/chapter/1' => '<img class="pic" src="/images/1.jpg">',
        _ => throw StateError('unexpected request: ${request.url}'),
      };
      return http.Response(
        body,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final source = ComicSource.fromPpcatFlat({
      'bookSourceName': '双字段测试源',
      'bookSourceUrl': 'https://comic.example',
      'ruleChapterList': '.chapters li',
      'ruleChapterName': 'tag.a@text',
      'ruleContentUrl': 'tag.a@href',
      'ruleChapterUrl': 'id.btn_expandChapterList@href',
      'ruleBookContent': 'img.pic@src',
    });
    final runtime = SourceRuntime(
      source: source,
      fetcher: HttpFetcher(client: client),
    );
    final (_, chapters) = await runtime.detail('https://comic.example/comic/1');
    expect(chapters.map((chapter) => chapter.title), ['第1话', '第2话']);
    expect(chapters.map((chapter) => chapter.url), [
      'https://comic.example/chapter/1',
      'https://comic.example/chapter/2',
    ]);
    expect(await runtime.images(chapters.first.url), [
      'https://comic.example/images/1.jpg',
    ]);
    expect(requested.map((uri) => uri.path), ['/comic/1', '/chapter/1']);
  });
}
