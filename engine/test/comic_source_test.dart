import 'dart:convert';
import 'dart:io';

import 'package:engine/src/models/comic_source.dart';
import 'package:engine/src/store/repo_client.dart';
import 'package:test/test.dart';

void main() {
  group('ComicSource 模型', () {
    test('ppcat 平铺键 → 嵌套规则', () {
      final s = ComicSource.fromPpcatFlat({
        'ruleId': 'src-1',
        'sourceName': '测试源',
        'sourceGroup': '测试组',
        'sourceUrl': 'https://m.example.com',
        'enabled': true,
        'weight': 5,
        'ruleSearchList': 'class.item',
        'ruleSearchName': 'class.title@text',
        'ruleSearchNoteUrl': 'a@href',
        'ruleChapterList': 'class.chapter',
        'ruleContentUrl': 'tag.a@href',
        'ruleBookContent': 'img.pic@src',
      });
      expect(s.id, 'src-1');
      expect(s.name, '测试源');
      expect(s.weight, 5);
      expect(s.rules.searchList, 'class.item');
      expect(s.rules.searchName, 'class.title@text');
      expect(s.rules.searchBookUrl, 'a@href');
      expect(s.rules.chapterList, 'class.chapter');
      // 真实语义：ruleContentUrl=章节链接，ruleBookContent=取图规则
      expect(s.rules.chapterUrl, 'tag.a@href');
      expect(s.rules.contentUrl, 'img.pic@src');
    });

    test('ruleSearchUrl 平铺键归一到 rules.searchUrl', () {
      final s = ComicSource.fromPpcatFlat({
        'bookSourceName': '腾讯漫画（正版）',
        'bookSourceUrl': 'https://m.ac.qq.com',
        'ruleSearchUrl':
            '/search/result?word=searchKey&page=searchPage&pageSize=30&style=items',
        'ruleSearchList': 'class.item',
        'headers': {'User-Agent': 'Android'},
      });
      expect(s.rules.searchUrl, contains('searchKey'));
      expect(s.headers['User-Agent'], 'Android');
    });

    test('searchUrl 与 ruleSearchUrl 任一非空即可；两者并存时 searchUrl 优先', () {
      final viaNestedName = ComicSource.fromPpcatFlat({
        'bookSourceName': '甲',
        'bookSourceUrl': 'https://m.example.com',
        'searchUrl': 'https://m.example.com/search?q={{key}}',
      });
      expect(viaNestedName.rules.searchUrl, contains('{{key}}'));

      final both = ComicSource.fromPpcatFlat({
        'bookSourceName': '乙',
        'bookSourceUrl': 'https://m.example.com',
        'ruleSearchUrl': '/legacy?q=searchKey',
        'searchUrl': 'https://m.example.com/search?q={{key}}',
      });
      expect(both.rules.searchUrl, contains('{{key}}'));
    });

    test('fromJson 顶层 ruleSearchUrl 同样归一', () {
      final s = ComicSource.fromJson({
        'id': 'https://m.example.com',
        'name': '丙',
        'url': 'https://m.example.com',
        'ruleSearchUrl': '/search?q=searchKey',
      });
      expect(s.rules.searchUrl, '/search?q=searchKey');
    });

    test('嵌套 JSON 往返', () {
      final s = ComicSource.fromJson({
        'id': 'a1',
        'name': '甲',
        'enabled': true,
        'headers': {'Referer': 'https://img.example.com'},
        'rules': {
          'searchUrl': 'https://m.example.com/search?q={{key}}',
          'searchList': '.item',
          'searchName': '.title@text',
        },
      });
      expect(s.headers['Referer'], 'https://img.example.com');
      expect(s.rules.searchUrl, contains('{{key}}'));
      final back = ComicSource.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.rules.searchList, '.item');
      expect(back.name, '甲');
    });

    test('健康字段往返保真（失败计数/原因/时间）', () {
      final s = ComicSource.fromJson({
        'id': 'h1',
        'name': '失效源',
        'lastError': 'HTTP 404 for https://x.example.com/s',
        'lastFailedAt': 1757150000000,
        'failCount': 4,
        'lastOkAt': 1757000000000,
      });
      expect(s.failCount, 4);
      expect(s.isUnhealthy, isTrue);
      final back = ComicSource.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.lastError, s.lastError);
      expect(back.lastFailedAt, 1757150000000);
      expect(back.failCount, 4);
      expect(back.lastOkAt, 1757000000000);
    });

    test('健康字段缺省与错型容错（老快照兼容）', () {
      final s = ComicSource.fromJson({'id': 'h2', 'failCount': 'oops'});
      expect(s.failCount, 0);
      expect(s.isUnhealthy, isFalse);
      expect(s.lastError, '');
      final back = ComicSource.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.toJson().containsKey('failCount'), isFalse);
    });

    test('fromPpcatFlat 导入的源健康字段为零值', () {
      final s = ComicSource.fromPpcatFlat({
        'bookSourceName': '新源',
        'bookSourceUrl': 'https://m.example.com',
        'ruleSearchUrl': '/search?q=searchKey',
      });
      expect(s.failCount, 0);
      expect(s.lastOkAt, 0);
      expect(s.isUnhealthy, isFalse);
    });

    test('内置快照多数源导入后 searchUrl 非空', () {
      final snapshot = File('../store-snapshot/store.json');
      expect(snapshot.existsSync(), isTrue, reason: '需从 engine/ 目录运行 dart test');
      final j = jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
      final list = (j['sources'] as List).whereType<Map<String, dynamic>>().toList();
      expect(list.length, greaterThan(400));

      final sources = list.map(ComicSource.fromPpcatFlat).toList();
      final provided = list.where((m) {
        final a = m['ruleSearchUrl'];
        final b = m['searchUrl'];
        return (a is String && a.isNotEmpty) || (b is String && b.isNotEmpty);
      }).length;
      final imported = sources.where((s) => s.rules.searchUrl.isNotEmpty).length;
      expect(provided, greaterThan(400));
      expect(imported, provided);

      final headerMaps = list.where((m) => m['headers'] is Map && (m['headers'] as Map).isNotEmpty).length;
      expect(sources.where((s) => s.headers.isNotEmpty).length, greaterThanOrEqualTo(headerMaps));
    });
  });

  group('RepoRef 解析', () {
    test('GitHub 完整 URL', () {
      final r = RepoRef.parse('https://github.com/AcgLibrary/ppcat_store')!;
      expect(r.host, 'github');
      expect(r.user, 'AcgLibrary');
      expect(r.repo, 'ppcat_store');
      expect(r.rawCandidates('store').first,
          'https://raw.githubusercontent.com/AcgLibrary/ppcat_store/master/store');
    });

    test('Gitee URL', () {
      final r = RepoRef.parse('https://gitee.com/user/repo')!;
      expect(r.host, 'gitee');
      expect(r.rawCandidates('meta.json').first, 'https://gitee.com/user/repo/raw/master/meta.json');
    });

    test('user/repo 简写', () {
      final r = RepoRef.parse('AcgLibrary/ppcat_store')!;
      expect(r.canonical, 'github.com/AcgLibrary/ppcat_store');
    });

    test('无法识别返回 null', () {
      expect(RepoRef.parse('ftp://example.com/foo'), isNull);
      expect(RepoRef.parse('https://example.com/foo')?.isListUrl, isTrue);
    });

    test('jsdelivr 兜底候选存在', () {
      final r = RepoRef.parse('github.com/u/r')!;
      expect(r.rawCandidates('x').any((u) => u.contains('cdn.jsdelivr.net')), isTrue);
    });
  });
}
