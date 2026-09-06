import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/backup_service.dart';
import 'package:comic_forge/state/app_state.dart';

AppState _populated() {
  final st = AppState();
  final src = ComicSource.fromPpcatFlat({
    'bookSourceName': '源A',
    'bookSourceUrl': 'https://m.example.com/a',
    'ruleSearchUrl': '/s?q=searchKey',
  });
  st.sources.add(src);
  st.shelf.add(Book.fromJson({'name': '书一', 'bookUrl': 'https://m.example.com/b/1', 'sourceId': 'x'}));
  st.progress['https://m.example.com/b/1'] = ReadingProgress(
      bookUrl: 'https://m.example.com/b/1',
      sourceId: 'x',
      chapterUrl: 'c1',
      chapterTitle: '第1话',
      chapterIndex: 0,
      chapterCount: 5,
      at: 100);
  st.repos.add('https://github.com/u/r');
  return st;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupService 导出/合并导入', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('导出→导入 round-trip：四类数据合并到位', () async {
      final src = _populated();
      final text = BackupService.exportJson(src);

      final dst = AppState(); // 空目标
      final r = await BackupService.importJson(dst, text);
      expect(r.sources, 1);
      expect(r.shelf, 1);
      expect(r.progress, 1);
      expect(r.repos, 1);
      expect(dst.sources.first.name, '源A');
      expect(dst.shelf.first.name, '书一');
      expect(dst.progress['https://m.example.com/b/1']!.chapterTitle, '第1话');
      expect(dst.repos.first, contains('github.com'));
    });

    test('合并语义：源按 id 替换保留启停、书架并集、进度取较新', () async {
      final src = _populated();
      final text = BackupService.exportJson(src);

      final dst = AppState();
      // 目标已有同 id 源（不同规则）+ 已禁用
      final existing = ComicSource.fromPpcatFlat({
        'bookSourceName': '源A旧',
        'bookSourceUrl': 'https://m.example.com/a',
        'ruleSearchUrl': '/old?q=1',
      });
      existing.enabled = false;
      dst.sources.add(existing);
      // 目标已有同书进度（较旧 at=50）与不同书
      dst.progress['https://m.example.com/b/1'] = ReadingProgress(
          bookUrl: 'https://m.example.com/b/1',
          sourceId: 'x',
          chapterUrl: 'c0',
          chapterTitle: '序章',
          chapterIndex: 0,
          chapterCount: 5,
          at: 50);

      final r = await BackupService.importJson(dst, text);
      expect(r.sources, 1, reason: '指纹不同应替换');
      expect(dst.sources.first.rules.searchUrl, '/s?q=searchKey');
      expect(dst.sources.first.enabled, isFalse, reason: '替换保留本地启停');

      expect(dst.shelf, hasLength(1));
      expect(dst.progress['https://m.example.com/b/1']!.chapterTitle, '第1话',
          reason: '备份进度较新应胜出');

      // 进度较旧的反向场景：本地 at 更大则保留本地
      src.progress['https://m.example.com/b/1'] = ReadingProgress(
          bookUrl: 'https://m.example.com/b/1',
          sourceId: 'x',
          chapterUrl: 'c1',
          chapterTitle: '第1话',
          chapterIndex: 0,
          chapterCount: 5,
          at: 10);
      final text2 = BackupService.exportJson(src);
      await BackupService.importJson(dst, text2);
      expect(dst.progress['https://m.example.com/b/1']!.at, 100);
    });

    test('坏格式拒绝并给出可读错误', () async {
      final st = AppState();
      expect(BackupService.tryParse('not json'), isNull);
      expect(
          () => BackupService.importJson(st, '{"app":"other"}'),
          throwsA(predicate<FormatException>(
              (e) => e.message.contains('格式不正确'))));
    });

    test('持久化生效：导入后重载（load 路径）数据仍在', () async {
      final src = _populated();
      final text = BackupService.exportJson(src);
      final dst = AppState();
      await BackupService.importJson(dst, text);

      final re = AppState();
      await re.load();
      expect(re.sources, hasLength(1));
      expect(re.shelf, hasLength(1));
      expect(re.progress, contains('https://m.example.com/b/1'));
      expect(re.repos, hasLength(1));
    });
  });

  group('BackupService WebDAV 端到端（MockClient）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('备份→恢复 round-trip（内存假服务器，含目录创建与认证头）', () async {
      String? stored;
      final seen = <(String, String)>[];
      final mock = MockClient((req) async {
        seen.add((req.method, req.url.toString()));
        switch (req.method) {
          case 'MKCOL':
            return http.Response('', 201);
          case 'PUT':
            stored = utf8.decode(req.bodyBytes);
            return http.Response('', 201);
          case 'GET':
            return stored == null
                ? http.Response('', 404)
                : http.Response.bytes(utf8.encode(stored!), 200);
        }
        return http.Response('', 405);
      });

      final src = _populated();
      await BackupService.backupToWebDav(
        st: src,
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
        client: mock,
      );
      expect(stored, contains('"app":"comic-forge"'));
      expect(seen.where((e) => e.$1 == 'MKCOL'), isNotEmpty,
          reason: '上传前应逐级建目录');
      expect(seen.any((e) => e.$2 == 'https://dav.example.com/comic-forge/backup.json'),
          isTrue);

      final dst = AppState();
      final r = await BackupService.restoreFromWebDav(
        st: dst,
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
        client: mock,
      );
      expect(r.sources, 1);
      expect(dst.sources.first.name, '源A');
      expect(dst.shelf.first.name, '书一');
    });
  });
}
