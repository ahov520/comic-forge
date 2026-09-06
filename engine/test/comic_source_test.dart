import 'dart:convert';

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
      expect(RepoRef.parse('https://example.com/foo'), isNull);
    });

    test('jsdelivr 兜底候选存在', () {
      final r = RepoRef.parse('github.com/u/r')!;
      expect(r.rawCandidates('x').any((u) => u.contains('cdn.jsdelivr.net')), isTrue);
    });
  });
}
