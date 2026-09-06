import 'dart:convert';

import 'package:engine/src/models/comic_source.dart';
import 'package:engine/src/net/fetcher.dart';
import 'package:engine/src/source_runtime.dart';
import 'package:test/test.dart';

/// 内存 Fake：URL → 文本。
class FakeFetcher implements Fetcher {
  FakeFetcher(this.routes);

  final Map<String, String> routes;
  final List<String> requested = [];

  @override
  Future<String> getString(String url, {Map<String, String>? headers, String? charset}) async {
    requested.add(url);
    final hit = routes[url] ?? routes[_stripQuery(url)];
    if (hit == null) throw FetchException('no route for $url');
    return hit;
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    return utf8.encode(await getString(url, headers: headers));
  }

  static String _stripQuery(String url) => url.split('?').first;
}

const searchPage = '''
<html><body><div class="list">
  <div class="item">
    <a class="title" href="/comic/1">海贼王</a>
    <span class="author">尾田</span>
    <img class="cover" src="/img/op.jpg"/>
  </div>
  <div class="item">
    <a class="title" href="/comic/2">火影</a>
    <span class="author">岸本</span>
    <img class="cover" src="/img/nr.jpg"/>
  </div>
</div>
<a class="next" href="/search?page=2">下一页</a>
</body></html>
''';

const detailPage = '''
<html><body>
  <h1 class="name">海贼王</h1>
  <span class="author">尾田荣一郎</span>
  <img class="cover" src="https://img.example.com/op.jpg"/>
  <p class="intro">要成为海贼王的男人</p>
  <div class="chapters">
    <a class="ch" href="/comic/1/1">第1话</a>
    <a class="ch" href="/comic/1/2">第2话</a>
  </div>
</body></html>
''';

const chapterPage = '''
<html><body><div class="pics">
  <img class="pic" src="https://img.example.com/p1.jpg"/>
  <img class="pic" src="https://img.example.com/p2.jpg"/>
  <a class="next-page" href="?part=2">下一页</a>
</div></body></html>
''';

const chapterPage2 = '''
<html><body><div class="pics">
  <img class="pic" src="https://img.example.com/p3.jpg"/>
</div></body></html>
''';

ComicSource buildSource() => ComicSource.fromJson({
      'id': 'test',
      'name': '测试源',
      'url': 'https://m.example.com',
      'rules': {
        'searchUrl': 'https://m.example.com/search?q={{key}}&page={{page}}',
        'searchList': '.item',
        'searchName': '.title@text',
        'searchAuthor': '.author@text',
        'searchCoverUrl': 'img@src',
        'searchBookUrl': 'a.title@href',
        'searchUrlNext': '.next@href',
        'bookName': '.name@text',
        'bookAuthor': '.author@text',
        'bookCoverUrl': '.cover@src',
        'bookIntroduce': '.intro@text',
        'chapterList': '.chapters a',
        'chapterName': '@text',
        'chapterUrl': '@href',
        'contentUrl': 'img.pic@src',
        'contentUrlNext': '.next-page@href',
      },
    });

void main() {
  group('SourceRuntime 全链路', () {
    late FakeFetcher fetcher;
    late SourceRuntime rt;

    setUp(() {
      fetcher = FakeFetcher({
        'https://m.example.com/search?q=%E6%B5%B7%E8%B4%BC&page=1': searchPage,
        'https://m.example.com/comic/1': detailPage,
        'https://m.example.com/comic/1/1': chapterPage,
        'https://m.example.com/comic/1/1?part=2': chapterPage2,
      });
      rt = SourceRuntime(source: buildSource(), fetcher: fetcher);
    });

    test('搜索 → 列表与相对链接转绝对', () async {
      final page = await rt.search('海贼', page: 1);
      expect(page.items.length, 2);
      expect(page.items.first.name, '海贼王');
      expect(page.items.first.author, '尾田');
      expect(page.items.first.coverUrl, 'https://m.example.com/img/op.jpg');
      expect(page.items.first.bookUrl, 'https://m.example.com/comic/1');
      expect(page.nextPage, 'https://m.example.com/search?page=2');
    });

    test('详情 + 章节', () async {
      final (book, chapters) = await rt.detail('https://m.example.com/comic/1');
      expect(book.name, '海贼王');
      expect(book.introduce, '要成为海贼王的男人');
      expect(chapters.length, 2);
      expect(chapters.first.title, '第1话');
      expect(chapters.first.url, 'https://m.example.com/comic/1/1');
    });

    test('章节图片 + UrlNext 翻页', () async {
      final imgs = await rt.images('https://m.example.com/comic/1/1');
      expect(imgs, [
        'https://img.example.com/p1.jpg',
        'https://img.example.com/p2.jpg',
        'https://img.example.com/p3.jpg',
      ]);
      expect(fetcher.requested.where((u) => u.contains('part=2')).length, 1);
    });
  });

  group('JSON API 型源', () {
    test('jsonpath 规则', () async {
      final fetcher = FakeFetcher({
        'https://api.example.com/search?q=a': jsonEncode({
          'data': {
            'list': [
              {'title': '甲', 'url': '/book/1', 'cover': 'https://img.example.com/1.jpg'},
              {'title': '乙', 'url': '/book/2', 'cover': 'https://img.example.com/2.jpg'},
            ]
          }
        }),
      });
      final src = ComicSource.fromJson({
        'id': 'api',
        'name': 'API源',
        'rules': {
          'searchUrl': 'https://api.example.com/search?q={{key}}',
          'searchList': '\$.data.list[*]',
          'searchName': '\$.title',
          'searchBookUrl': '\$.url',
          'searchCoverUrl': '\$.cover',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      final page = await rt.search('a');
      expect(page.items.length, 2);
      expect(page.items.first.name, '甲');
      expect(page.items.first.coverUrl, 'https://img.example.com/1.jpg');
    });
  });
}
