import 'dart:convert';

import 'package:engine/src/models/comic_source.dart';
import 'package:engine/src/net/fetcher.dart';
import 'package:engine/src/net/request.dart';
import 'package:engine/src/source_runtime.dart';
import 'package:test/test.dart';

/// 内存 Fake：URL → 文本。
class FakeFetcher implements Fetcher {
  FakeFetcher(this.routes);

  final Map<String, String> routes;
  final List<String> requested = [];
  final List<SourceRequest> sentRequests = [];

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

  @override
  Future<List<int>> send(SourceRequest request, {Map<String, String>? headers}) async {
    sentRequests.add(request);
    return utf8.encode(await getString(request.url, headers: {...request.headers, ...?headers}));
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

  group('POST 搜索（ppcat @ 语法穿透全链路）', () {
    test('表单体搜索：method/body/content-type 到达抓取器', () async {
      final fetcher = FakeFetcher({
        'https://api.example.com/search': jsonEncode({
          'list': [
            {'title': '丙', 'url': '/book/9'},
          ]
        }),
      });
      final src = ComicSource.fromJson({
        'id': 'post',
        'name': 'POST源',
        'url': 'https://api.example.com',
        'rules': {
          'searchUrl': '/search@page={{page}}&key={{key}}',
          'searchList': '\$.list[*]',
          'searchName': '\$.title',
          'searchBookUrl': '\$.url',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      final page = await rt.search('海贼');
      expect(page.items.single.name, '丙');
      expect(fetcher.sentRequests.single.isPost, isTrue);
      expect(fetcher.sentRequests.single.body, 'page=1&key=%E6%B5%B7%E8%B4%BC');
      expect(
          fetcher.sentRequests.single.headers['Content-Type'],
          'application/x-www-form-urlencoded');
      expect(fetcher.sentRequests.single.headers['User-Agent'], isNotEmpty);
    });

    test('PostJson + 算术页码', () async {
      final fetcher = FakeFetcher({
        'https://api.example.com/twirp/Search': '{"list":[]}',
      });
      final src = ComicSource.fromJson({
        'id': 'pj',
        'name': 'PostJson源',
        'url': 'https://api.example.com',
        'rules': {
          'searchUrl': '/twirp/Search@{"page_num":searchPage-1}@PostJson',
          'searchList': '\$.list[*]',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      await rt.search('x', page: 2);
      final req = fetcher.sentRequests.single;
      expect(req.isPost, isTrue);
      expect(req.body, '{"page_num":1}');
      expect(req.headers['Content-Type'], contains('application/json'));
    });
  });

  group('快看式 JSON 源（快看修复回归）', () {
    test(r'jsonpath 无 [*] 的数组摊平 + {$.id} bookUrl 模板', () async {
      final fetcher = FakeFetcher({
        'https://www.kkmh.example.com/v1/search/topic?q=%E6%96%97%E7%BD%97&since=0&count=48':
            jsonEncode({
          'code': 200,
          'data': {
            'hit': [
              {'id': 3095, 'title': '斗罗大陆外传'},
              {'id': 4096, 'title': '斗罗大陆'},
            ],
          },
        }),
      });
      final src = ComicSource.fromJson({
        'id': 'kkmh',
        'name': '快看式源',
        'url': 'https://www.kkmh.example.com',
        'rules': {
          'searchUrl': '/v1/search/topic?q={{key}}&since={{48*(searchPage-1)}}&count=48',
          'searchList': '\$.data.hit||\$.data.topics',
          'searchName': '\$.title',
          'searchBookUrl': 'https://www.kkmh.example.com/web/topic/{\$.id}/',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      final page = await rt.search('斗罗');
      expect(page.items.length, 2, reason: '命中数组应摊平为逐项节点');
      expect(page.items.first.name, '斗罗大陆外传');
      expect(page.items.first.bookUrl, 'https://www.kkmh.example.com/web/topic/3095/',
          reason: r'{$.id} 字面模板应代入条目字段');
      expect(page.items.last.bookUrl, 'https://www.kkmh.example.com/web/topic/4096/');
    });

    test('B站式规则全链路：POST搜索 + {{js}}列表 + @js: bookUrl模板 + POST详情', () async {
      final fetcher = FakeFetcher({
        'https://manga.bili.example.com/twirp/comic.v1.Comic/Search': jsonEncode({
          'data': {
            'list': [
              {'id': 30956, 'org_title': '某科学的超电磁炮', 'title': '科学超电磁炮'},
              {'id': 27036, 'org_title': '灵笼', 'title': '灵笼月魁传'},
            ],
          },
        }),
        'https://manga.bili.example.com/twirp/comic.v1.Comic/ComicDetail?device=h5&platform=h5':
            jsonEncode({
          'data': {
            'title': '某科学的超电磁炮',
            'chapter_list': [
              {'id': 1, 'short_title': '第1话', 'url': '/reader/1'},
              {'id': 2, 'short_title': '第2话', 'url': '/reader/2'},
            ],
          },
        }),
      });
      final src = ComicSource.fromJson({
        'id': 'bili',
        'name': 'B站式源',
        'url': 'https://manga.bili.example.com',
        'headers': {'User-Agent': 'Android'},
        'rules': {
          'searchUrl': '/twirp/comic.v1.Comic/Search'
              '@{"platform":"h5","key_word":"searchKey","pageSize":10,"page_num":searchPage}'
              '@Header:{"Content-Type":"application/json;charset=UTF-8"}@PostJson',
          'searchList': "{{\nvar json=JSON.parse(result);\n"
              "var out='\$.data.list.*|\$.data.*';\n"
              "if(json.data.list&&json.data.list.length==0){\nout=undefined;\n}\nout\n}}",
          'searchName': r'$.org_title|$.title@put:{pid:$.id|$.season_id}'
              '@js:java.fns.diableList=java.ajax("x");result',
          'searchBookUrl': r'''$.id|$.season_id@js:
'https://manga.bili.example.com/twirp/comic.v1.Comic/ComicDetail?device=h5&platform=h5@{"comic_id":'+result+'}@PostJson'
''',
          'bookName': r'$.data.title',
          'chapterList': r'$.data.chapter_list[*]',
          'chapterName': r'$.short_title',
          'chapterUrl': r'$.url',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      final page = await rt.search('超电磁炮');
      expect(page.items.length, 2, reason: '{{js}}列表块应静态求值为 jsonpath');
      expect(page.items.first.name, '某科学的超电磁炮', reason: '@put/@js 不可解析时回退前缀提取');
      final detailUrl = page.items.first.bookUrl;
      expect(detailUrl, contains('"comic_id":30956'), reason: r'@js: 拼接模板应代入 $.id');
      expect(detailUrl, contains('@PostJson'));

      final (book, chapters) = await rt.detail(detailUrl);
      expect(book.name, '某科学的超电磁炮');
      expect(chapters.map((c) => c.title), ['第1话', '第2话']);
      final detailReq = fetcher.sentRequests
          .firstWhere((r) => r.url.contains('ComicDetail'));
      expect(detailReq.isPost, isTrue);
      expect(detailReq.body, contains('"comic_id":30956'));
    });
  });

  group('JS 取图（JsHook 注入）', () {
    test('规则求值失败时回退 JS 钩子，结果支持换行/JSON 数组', () async {
      final fetcher = FakeFetcher({
        'https://m.example.com/c/1': '<html><body>div内容，无 img 规则命中</body></html>',
        'https://m.example.com/c/2': '<html><body>page2</body></html>',
      });
      final src = ComicSource.fromJson({
        'id': 'jsimg',
        'name': 'JS取图源',
        'url': 'https://m.example.com',
        'rules': {
          'contentUrl': r'''
$function getImgList(html) {
  return ['https://img.example.com/p1.jpg', '/img/p2.jpg'];
}
getImgList(html)''',
        },
      });
      final calls = <Map<String, dynamic>>[];
      Future<String?> hook(String code, Map<String, dynamic> env) async {
        calls.add(env);
        return 'https://img.example.com/p1.jpg\n/img/p2.jpg';
      }

      final rt = SourceRuntime(source: src, fetcher: fetcher, jsHook: hook);
      final imgs = await rt.images('https://m.example.com/c/1');
      expect(imgs, [
        'https://img.example.com/p1.jpg',
        'https://m.example.com/img/p2.jpg',
      ], reason: 'JS 结果按换行拆分并绝对化');
      expect(calls, hasLength(1));
      expect(calls.single['html'], contains('div内容'));
      expect(calls.single['baseUrl'], 'https://m.example.com/c/1');
    });

    test('JSON 数组形式结果', () async {
      final fetcher = FakeFetcher({'https://m.example.com/c/9': '<html>x</html>'});
      final src = ComicSource.fromJson({
        'id': 'jsjson',
        'name': 'JS JSON源',
        'url': 'https://m.example.com',
        'rules': {'contentUrl': r'$function getImgList(html){return []}'},
      });
      final rt = SourceRuntime(
        source: src,
        fetcher: fetcher,
        jsHook: (code, env) async =>
            jsonEncode([{'url': 'https://img.example.com/a.jpg'}]),
      );
      expect(await rt.images('https://m.example.com/c/9'),
          ['https://img.example.com/a.jpg']);
    });

    test('jsonpath 规则不触发 JS 回退；无钩子时 JS 规则静默为空', () async {
      final fetcher = FakeFetcher({'https://m.example.com/c/3': '{"pics":["/a.jpg"]}'});
      // 1) jsonpath 规则 + 钩子存在但不应被调用
      var hookCalled = false;
      final src1 = ComicSource.fromJson({
        'id': 'jp',
        'url': 'https://m.example.com',
        'rules': {'contentUrl': r'$.pics[*]'},
      });
      final rt1 = SourceRuntime(source: src1, fetcher: fetcher, jsHook: (c, e) async {
        hookCalled = true;
        return null;
      });
      expect(await rt1.images('https://m.example.com/c/3'),
          ['https://m.example.com/a.jpg']);
      expect(hookCalled, isFalse, reason: 'jsonpath 不算 JS 形态');

      // 2) JS 规则 + 无钩子 → 空列表不抛错
      final src2 = ComicSource.fromJson({
        'id': 'js2',
        'url': 'https://m.example.com',
        'rules': {'contentUrl': r'$function getImgList(html){}'},
      });
      final rt2 = SourceRuntime(source: src2, fetcher: fetcher);
      expect(await rt2.images('https://m.example.com/c/3'), isEmpty);
    });

    test('ruleChapterUrlNext 章节列表翻页（去重合并）', () async {
      const detailP1 = '''
<html><body><h1 class="name">翻页书</h1>
<div class="chapters"><a class="ch" href="/c/1">第1话</a><a class="ch" href="/c/2">第2话</a></div>
<a class="next" href="/book/1?p=2">下一页</a></body></html>''';
      const detailP2 = '''
<html><body><div class="chapters"><a class="ch" href="/c/3">第3话</a></div>
</body></html>''';
      final fetcher = FakeFetcher({
        'https://m.example.com/book/1': detailP1,
        'https://m.example.com/book/1?p=2': detailP2,
      });
      final src = ComicSource.fromJson({
        'id': 'pg',
        'name': '翻页源',
        'url': 'https://m.example.com',
        'rules': {
          'bookName': '.name@text',
          'chapterList': '.chapters a',
          'chapterName': '@text',
          'chapterUrl': '@href',
          'chapterUrlNext': 'a.next@href',
        },
      });
      final rt = SourceRuntime(source: src, fetcher: fetcher);
      final (book, chapters) = await rt.detail('https://m.example.com/book/1');
      expect(book.name, '翻页书');
      expect(chapters.map((c) => c.title), ['第1话', '第2话', '第3话']);
      expect(chapters.last.url, 'https://m.example.com/c/3');
    });

    test('无 chapterUrlNext 时单页章节照常（回归）', () async {
      final fetcher = FakeFetcher({'https://m.example.com/comic/1': detailPage});
      final rt = SourceRuntime(source: buildSource(), fetcher: fetcher);
      final (_, chapters) = await rt.detail('https://m.example.com/comic/1');
      expect(chapters.length, 2);
    });
  });
}
