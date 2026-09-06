import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/source_form.dart';

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
          (SourceForm.build(name: '', url: 'https://m.example.com') as SourceBuildError)
              .message,
          '名称必填');
      expect(
          (SourceForm.build(name: '甲', url: '') as SourceBuildError).message, '源地址必填');
      expect(
          (SourceForm.build(name: '甲', url: 'http://127.0.0.1/x') as SourceBuildError).message,
          contains('公网'));
      expect(
          (SourceForm.build(name: '甲', url: 'https://m.example.com') as SourceBuildError)
              .message,
          contains('至少填一个'));
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
