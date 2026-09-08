import 'dart:convert';

import 'package:comic_forge/backup_service.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/search_filters.dart';
import 'package:comic_forge/state/shelf_sort.dart';
import 'package:comic_forge/state/shelf_update_schedule.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppState _populated() {
  final st = AppState();
  final src = ComicSource.fromPpcatFlat({
    'bookSourceName': '源A',
    'bookSourceUrl': 'https://m.example.com/a',
    'ruleSearchUrl': '/s?q=searchKey',
  });
  st.sources.add(src);
  st.shelf.add(
    Book.fromJson({
      'name': '书一',
      'bookUrl': 'https://m.example.com/b/1',
      'sourceId': 'x',
    }),
  );
  st.progress['https://m.example.com/b/1'] = ReadingProgress(
    bookUrl: 'https://m.example.com/b/1',
    sourceId: 'x',
    chapterUrl: 'c1',
    chapterTitle: '第1话',
    chapterIndex: 0,
    chapterCount: 5,
    at: 100,
  );
  st.repos.add('https://github.com/u/r');
  return st;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupService 导出/合并导入', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      SourceService.instance.adBlock = null;
      SourceService.instance.debugResetNetworkPolicy();
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
        at: 50,
      );

      final r = await BackupService.importJson(dst, text);
      expect(r.sources, 1, reason: '指纹不同应替换');
      expect(dst.sources.first.rules.searchUrl, '/s?q=searchKey');
      expect(dst.sources.first.enabled, isFalse, reason: '替换保留本地启停');

      expect(dst.shelf, hasLength(1));
      expect(
        dst.progress['https://m.example.com/b/1']!.chapterTitle,
        '第1话',
        reason: '备份进度较新应胜出',
      );

      // 进度较旧的反向场景：本地 at 更大则保留本地
      src.progress['https://m.example.com/b/1'] = ReadingProgress(
        bookUrl: 'https://m.example.com/b/1',
        sourceId: 'x',
        chapterUrl: 'c1',
        chapterTitle: '第1话',
        chapterIndex: 0,
        chapterCount: 5,
        at: 10,
      );
      final text2 = BackupService.exportJson(src);
      await BackupService.importJson(dst, text2);
      expect(dst.progress['https://m.example.com/b/1']!.at, 100);
    });

    test('坏格式拒绝并给出可读错误', () async {
      final st = AppState();
      expect(BackupService.tryParse('not json'), isNull);
      expect(
        () => BackupService.importJson(st, '{"app":"other"}'),
        throwsA(predicate<FormatException>((e) => e.message.contains('格式不正确'))),
      );
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

    test('v2 导出含历史、书签和设置，合并后跨重启保留', () async {
      final src = _populated();
      final book = src.shelf.first;
      src.darkMode = false;
      src.readerMode = 'paged';
      src.readerVolumeKeys = true;
      await src.setShelfSort(ShelfSort.title);
      await src.shelfUpdateSchedule.setEnabled(true);
      await src.shelfUpdateSchedule.setInterval(ShelfUpdateInterval.daily);
      await src.updateNotifications.setEnabled(true);
      await src.setAdBlock('{"urlRules":["ads"]}');
      await src.addBlockedDomain('blocked.example');
      await src.setSearchFilters(SearchFilters(onlyHealthy: true));
      await src.recordSearch('海贼王');
      await src.readingStats.record(
        book,
        Chapter(title: '第1话', url: 'c1'),
        from: DateTime.fromMillisecondsSinceEpoch(50),
        to: DateTime.fromMillisecondsSinceEpoch(80),
      );
      await src.toggleChapterBookmark(
        book,
        chapter: Chapter(title: '第1话', url: 'c1'),
        chapterIndex: 0,
      );
      final groupId = await src.shelfGroups.create('追更');
      await src.assignShelfGroups(book, [groupId]);
      await src.setReaderBrightness(0.4);
      await src.saveCurrentReaderPreset('夜间翻页');
      await src.saveProgress(
        book,
        chapterUrl: 'c1',
        chapterTitle: '第1话',
        chapterIndex: 0,
        chapterCount: 5,
      );
      final text = BackupService.exportJson(src);
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['version'], BackupService.formatVersion);
      expect(json['history'], isNotEmpty);
      expect(json['bookmarks'], isNotEmpty);
      expect(json['settings']['darkMode'], isFalse);
      expect(json['settings']['readerMode'], 'paged');
      expect(json.containsKey('webDav'), isFalse);
      expect(text, isNot(contains('pass')));

      final dst = AppState();
      addTearDown(dst.dispose);
      dst.darkMode = true;
      dst.shelf.add(
        Book.fromJson({
          'name': '本地书',
          'bookUrl': 'https://local.example/keep',
          'sourceId': 'local',
        }),
      );
      final r = await BackupService.importJson(dst, text);
      expect(r.shelf, 1);
      expect(dst.shelf.map((b) => b.name), containsAll(['书一', '本地书']));
      expect(dst.darkMode, isFalse);
      expect(dst.readerMode, 'paged');
      expect(dst.readerVolumeKeys, isTrue);
      expect(dst.shelfSort, ShelfSort.title);
      expect(dst.shelfUpdateSchedule.enabled, isTrue);
      expect(dst.shelfUpdateSchedule.interval, ShelfUpdateInterval.daily);
      expect(dst.updateNotifications.enabled, isTrue);
      expect(dst.adBlock, isNotNull);
      expect(dst.blockedDomains, contains('blocked.example'));
      expect(dst.searchFilters.onlyHealthy, isTrue);
      expect(dst.searchHistory, contains('海贼王'));
      expect(dst.chapterBookmarks, isNotEmpty);
      expect(dst.readingHistory, isNotEmpty);
      expect(dst.shelfGroups.groups.single.name, '追更');
      expect(dst.readingStats.forBook(book), isNotNull);
      expect(dst.readerPresets.presets.single.name, '夜间翻页');
      expect(dst.readerBrightness, 0.4);

      final re = AppState();
      addTearDown(re.dispose);
      await re.load();
      expect(re.darkMode, isFalse);
      expect(re.chapterBookmarks.single.chapter.url, 'c1');
      expect(re.readingHistory, isNotEmpty);
      expect(re.shelfGroups.groups.single.name, '追更');
      expect(re.blockedDomains, contains('blocked.example'));
      expect(re.readerPresets.presets.single.name, '夜间翻页');
    });

    test('覆盖导入替换集合，缺省的 v1 字段不改本地设置', () async {
      final dst = AppState();
      addTearDown(dst.dispose);
      dst.darkMode = false;
      dst.shelf.add(
        Book.fromJson({
          'name': '将被覆盖',
          'bookUrl': 'https://old.example/gone',
          'sourceId': 'old',
        }),
      );
      dst.repos.add('https://old.example/repo');
      await dst.toggleChapterBookmark(
        dst.shelf.first,
        chapter: Chapter(title: '旧书签', url: 'old-c'),
        chapterIndex: 1,
      );
      final v1 = jsonEncode({
        'app': 'comic-forge',
        'version': 1,
        'sources': [
          ComicSource.fromPpcatFlat({
            'bookSourceName': '源B',
            'bookSourceUrl': 'https://m.example.com/b',
            'ruleSearchUrl': '/q',
          }).toJson(),
        ],
        'shelf': [
          {
            'name': '新书',
            'bookUrl': 'https://m.example.com/new',
            'sourceId': 'n',
          },
        ],
        'progress': <String, dynamic>{},
        'repos': ['https://github.com/new/r'],
      });
      final r = await BackupService.importJson(
        dst,
        v1,
        mode: BackupImportMode.overwrite,
      );
      expect(r.shelf, 1);
      expect(dst.shelf.map((b) => b.name), ['新书']);
      expect(dst.repos, ['https://github.com/new/r']);
      expect(dst.chapterBookmarks, isNotEmpty, reason: 'v1 无书签字段，覆盖应保留本地书签');
      expect(dst.darkMode, isFalse, reason: 'v1 无设置字段，覆盖应保留本地外观');
    });

    test('覆盖导入会替换书签和设置；坏文件不改动现有数据', () async {
      final src = _populated();
      final book = src.shelf.first;
      await src.toggleChapterBookmark(
        book,
        chapter: Chapter(title: '第1话', url: 'c1'),
        chapterIndex: 0,
      );
      await src.setDark(false);
      final text = BackupService.exportJson(src);

      final dst = AppState();
      addTearDown(dst.dispose);
      dst.darkMode = true;
      final local = Book.fromJson({
        'name': '本地书',
        'bookUrl': 'https://local.example/keep',
        'sourceId': 'local',
      });
      dst.shelf.add(local);
      await dst.toggleChapterBookmark(
        local,
        chapter: Chapter(title: '本地签', url: 'local-c'),
        chapterIndex: 2,
      );
      await BackupService.importJson(
        dst,
        text,
        mode: BackupImportMode.overwrite,
      );
      expect(dst.shelf.map((b) => b.name), ['书一']);
      expect(dst.chapterBookmarks.map((e) => e.chapter.url), ['c1']);
      expect(dst.darkMode, isFalse);

      expect(
        () => BackupService.importJson(dst, '{"app":"other"}'),
        throwsA(isA<FormatException>()),
      );
      expect(dst.shelf.single.name, '书一');
      expect(dst.darkMode, isFalse);
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
      expect(
        seen.where((e) => e.$1 == 'MKCOL'),
        isNotEmpty,
        reason: '上传前应逐级建目录',
      );
      expect(
        seen.any(
          (e) => e.$2 == 'https://dav.example.com/comic-forge/backup.json',
        ),
        isTrue,
      );

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
