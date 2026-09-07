import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/clipboard_import.dart';
import 'package:comic_forge/state/source_form.dart';
import 'package:comic_forge/state/source_share.dart';

void main() {
  group('SourceForm.isPublicHttpUrl', () {
    test('放行公网 http/https', () {
      expect(SourceForm.isPublicHttpUrl('https://m.example.com'), isTrue);
      expect(SourceForm.isPublicHttpUrl('http://img.example.com/x'), isTrue);
    });

    test('拒绝非 http 与环回/私有/保留地址', () {
      expect(SourceForm.isPublicHttpUrl('ftp://m.example.com'), isFalse);
      expect(SourceForm.isPublicHttpUrl('localhost:8080'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://localhost/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://127.0.0.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://10.0.0.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://192.168.1.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://172.16.0.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://169.254.1.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://224.0.0.1/x'), isFalse);
      expect(SourceForm.isPublicHttpUrl('http://host.local'), isFalse);
      expect(SourceForm.isPublicHttpUrl('not a url'), isFalse);
      expect(SourceForm.isPublicHttpUrl(''), isFalse);
    });
  });

  group('SourceForm.build', () {
    test('必填校验：名称/地址/至少一个入口规则', () {
      expect(
        (SourceForm.build(name: '', url: 'https://m.example.com')
                as SourceBuildError)
            .message,
        '名称必填',
      );
      expect(
        (SourceForm.build(name: '甲', url: '') as SourceBuildError).message,
        '源地址必填',
      );
      expect(
        (SourceForm.build(name: '甲', url: 'http://127.0.0.1/x')
                as SourceBuildError)
            .message,
        contains('公网'),
      );
      expect(
        (SourceForm.build(name: '甲', url: 'https://m.example.com')
                as SourceBuildError)
            .message,
        contains('至少填一个'),
      );
    });

    test('构建成功：规则/headers 落位，id 缺省取 url', () {
      final r = SourceForm.build(
        name: '测试源',
        url: 'https://m.example.com',
        group: '测试组',
        headers: 'User-Agent: Android\nReferer=https://img.example.com',
        searchUrl: '/search?q=searchKey',
        searchList: 'class.item',
        searchName: 'class.title@text',
        searchBookUrl: 'tag.a@href',
        chapterList: 'class.ch',
        contentUrl: 'img@src',
      );
      final s = (r as SourceBuilt).source;
      expect(s.id, 'https://m.example.com');
      expect(s.name, '测试源');
      expect(s.group, '测试组');
      expect(s.headers['User-Agent'], 'Android');
      expect(s.headers['Referer'], 'https://img.example.com');
      expect(s.rules.searchUrl, '/search?q=searchKey');
      expect(s.rules.searchName, 'class.title@text');
      expect(s.rules.contentUrl, 'img@src');
    });

    test('编辑已有源：保留原 id（改 url 不换 id）', () {
      final r = SourceForm.build(
        existingId: 'https://old.example.com',
        name: '旧源',
        url: 'https://new.example.com',
        searchUrl: '/s',
      );
      expect((r as SourceBuilt).source.id, 'https://old.example.com');
    });

    test('编辑保留隐藏规则、源设置和健康记录，试跑副本不改动原源', () {
      final original = ComicSource.fromJson({
        'id': 'original-source',
        'name': '原源',
        'url': 'https://old.example.com',
        'icon': 'https://old.example.com/icon.png',
        'comment': '保留说明',
        'enabled': false,
        'weight': 27,
        'headers': {'User-Agent': 'Original'},
        'lastError': 'HTTP 503',
        'lastFailedAt': 200,
        'failCount': 3,
        'lastOkAt': 100,
        'rules': {
          'searchUrl': '/old-search',
          'searchUrlNext': '.search-next@href',
          'searchIntroduce': '.intro@text',
          'findList': '.discovery',
          'findName': '.name@text',
          'bookInit': '.book',
          'bookName': 'h1@text',
          'bookAuthor': '.author@text',
          'bookIntroduce': '.summary@text',
          'chapterInit': '.catalog',
          'chapterUrlNext': '.chapter-next@href',
          'contentInit': '.pages',
          'contentWebUrl': '.reader@href',
        },
      });
      final before = original.toJson();
      final updated =
          (SourceForm.build(
                    existing: original,
                    name: '新名称',
                    url: 'https://new.example.com',
                    searchUrl: '/new-search',
                    headers: 'User-Agent: Updated',
                  )
                  as SourceBuilt)
              .source;

      expect(updated.id, 'original-source');
      expect(updated.name, '新名称');
      expect(updated.url, 'https://new.example.com');
      expect(updated.rules.toJson(), {
        ...original.rules.toJson(),
        'searchUrl': '/new-search',
      });
      expect(updated.icon, original.icon);
      expect(updated.comment, original.comment);
      expect(updated.enabled, isFalse);
      expect(updated.weight, 27);
      expect(updated.lastError, 'HTTP 503');
      expect(updated.lastFailedAt, 200);
      expect(updated.failCount, 3);
      expect(updated.lastOkAt, 100);

      final shared =
          ClipboardSourceImport.parse(sourceShareJson(updated))
              as ClipboardImportSingle;
      expect(shared.source.name, '新名称');
      expect(shared.source.url, 'https://new.example.com');
      expect(shared.source.rules.searchUrl, '/new-search');
      expect(shared.source.rules.bookName, 'h1@text');
      expect(shared.source.lastError, isEmpty);

      updated.rules.bookName = '.trial-title@text';
      updated.headers['User-Agent'] = 'Trial';
      expect(original.toJson(), before);
    });

    test('编辑时明确清空的字段生效，发现入口不会回退旧 exploreUrl', () {
      final original = ComicSource.fromJson({
        'id': 'clear-source',
        'name': '待清空源',
        'url': 'https://m.example.com',
        'group': '旧分组',
        'headers': {'Referer': 'https://old.example.com'},
        'rules': {
          'searchUrl': '/search',
          'findUrl': '推荐::/featured',
          'exploreUrl': '旧入口::/old',
          'searchAuthor': '.author@text',
          'chapterName': 'a@text',
          'contentUrlNext': '.next@href',
          'bookName': 'h1@text',
        },
      });
      final updated =
          (SourceForm.build(
                    existing: original,
                    name: original.name,
                    url: original.url,
                    searchUrl: '/search',
                  )
                  as SourceBuilt)
              .source;

      expect(updated.group, isEmpty);
      expect(updated.headers, isEmpty);
      expect(updated.rules.toJson(), {
        'searchUrl': '/search',
        'bookName': 'h1@text',
      });
      expect(original.rules.findUrl, '推荐::/featured');
      expect(original.rules.exploreUrl, '旧入口::/old');
    });

    test('headers 非法行跳过不崩', () {
      final r = SourceForm.build(
        name: '甲',
        url: 'https://m.example.com',
        searchUrl: '/s',
        headers: '没有分隔符\n\nUser-Agent: X',
      );
      final s = (r as SourceBuilt).source;
      expect(s.headers, {'User-Agent': 'X'});
    });

    test('构建结果可持久化往返（toJson/fromJson）', () {
      final r = SourceForm.build(
        name: '往返源',
        url: 'https://m.example.com',
        searchUrl: '/s?q=searchKey',
        contentUrl: 'img@src',
      );
      final s = (r as SourceBuilt).source;
      final back = ComicSource.fromJson(s.toJson());
      expect(back.rules.searchUrl, '/s?q=searchKey');
      expect(back.name, '往返源');
    });
  });
}
