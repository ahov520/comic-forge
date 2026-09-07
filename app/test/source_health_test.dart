import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';

ComicSource _src(String id) => ComicSource.fromPpcatFlat({
      'bookSourceName': '源$id',
      'bookSourceUrl': 'https://m.example.com/$id',
      'ruleSearchUrl': '/search?q=searchKey',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState 源健康', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('失败回报累加计数，成功清零', () async {
      final st = AppState();
      final s = _src('a');
      await st.addSourceManual(s);
      await st.reportSourceHealth(const [], {s.id: 'HTTP 404'});
      expect(st.sources.first.failCount, 1);
      expect(st.sources.first.lastError, contains('404'));
      await st.reportSourceHealth(const [], {s.id: 'timeout'});
      expect(st.sources.first.failCount, 2);
      expect(st.sources.first.isUnhealthy, isFalse);

      await st.reportSourceHealth([s.id], const {});
      expect(st.sources.first.failCount, 0);
      expect(st.sources.first.lastError, '');
      expect(st.sources.first.lastOkAt, greaterThan(0));
    });

    test('未知 id 回报是 no-op', () async {
      final st = AppState();
      await st.addSourceManual(_src('z'));
      var notifications = 0;
      st.addListener(() => notifications++);
      await st.reportSourceHealth(const [], {'no-such-id': 'err'});
      await st.reportSourceHealth(['no-such-id'], const {});
      expect(st.sources.first.failCount, 0);
      expect(notifications, 0);
    });

    test('已健康源再次探测成功也保存最新成功时间，重启不会反复当作过期源', () async {
      final st = AppState();
      addTearDown(st.dispose);
      final s = _src('healthy-again')..lastOkAt = 1;
      await st.addSourceManual(s);
      await st.reportSourceHealth([s.id], const {});
      final sp = await SharedPreferences.getInstance();
      final saved = (jsonDecode(sp.getString('cf.sources')!) as List).single;
      expect(saved['lastOkAt'], s.lastOkAt);
      expect(saved['lastOkAt'], greaterThan(1));
    });

    test('连续失败≥3 → isUnhealthy，一键禁用后不再参与聚合搜索', () async {
      final st = AppState();
      final s = _src('b');
      await st.addSourceManual(s);
      for (var i = 0; i < 3; i++) {
        await st.reportSourceHealth(const [], {s.id: 'DNS lookup failed'});
      }
      expect(st.sources.first.isUnhealthy, isTrue);

      final n = await st.disableUnhealthySources();
      expect(n, 1);
      expect(st.sources.first.enabled, isFalse);

      // 聚合搜索与探索只挑 enabled 源
      final searchable =
          st.sources.where((s) => s.enabled && s.rules.searchUrl.isNotEmpty);
      expect(searchable, isEmpty);
    });

    test('健康记录持久化（按 load() 的读取路径还原仍在）', () async {
      final st = AppState();
      final s = _src('c');
      await st.addSourceManual(s);
      await st.reportSourceHealth(const [], {s.id: 'boom boom'});

      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('cf.sources')!;
      expect(raw, contains('boom boom'));

      // 与 AppState.load() 相同的反序列化路径
      final reloaded = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(ComicSource.fromJson)
          .toList();
      expect(reloaded.first.failCount, 1);
      expect(reloaded.first.lastError, 'boom boom');
      expect(reloaded.first.isUnhealthy, isFalse);
    });

    test('恢复内置源修复时保留健康记录', () async {
      final st = AppState();
      // 手动放入一个缺 searchUrl 的坏源（模拟旧版映射导入的脏数据）
      final broken =
          ComicSource.fromJson({'id': 'https://m.ac.qq.com', 'name': '腾讯漫画（正版）'});
      await st.addSourceManual(broken);
      await st.reportSourceHealth(const [], {'https://m.ac.qq.com': 'HTTP 403'});
      final failCountBefore = st.sources.first.failCount;

      final n = await st.importBuiltinSources();
      expect(n, greaterThanOrEqualTo(1));
      final fixed = st.sources.firstWhere((s) => s.id == 'https://m.ac.qq.com');
      expect(fixed.url, 'https://m.ac.qq.com');
      expect(fixed.rules.searchUrl, isNotEmpty, reason: '内置快照应补回 searchUrl');
      expect(fixed.rules.searchList, isNotEmpty, reason: '只有源 ID 的旧数据也需补齐列表规则');
      expect(fixed.rules.searchName, isNotEmpty);
      expect(fixed.failCount, failCountBefore, reason: '修复不应抹掉健康记录');
    });

    test('清除失败记录', () async {
      final st = AppState();
      final s = _src('d');
      await st.addSourceManual(s);
      await st.reportSourceHealth(const [], {s.id: 'x'});
      final n = await st.resetSourceHealth();
      expect(n, 1);
      expect(st.sources.first.failCount, 0);
      expect(st.sources.first.lastFailedAt, 0);
    });
  });

  group('AppState 阅读进度', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('保存后续读定位正确，且按 load() 路径还原', () async {
      final st = AppState();
      final book = Book.fromJson({'name': '测试书', 'bookUrl': 'https://m.example.com/b/1', 'sourceId': 's1'});
      await st.saveProgress(book,
          chapterUrl: 'https://m.example.com/b/1/c3',
          chapterTitle: '第3话',
          chapterIndex: 2,
          chapterCount: 10);
      expect(st.progressFor('https://m.example.com/b/1')!.chapterIndex, 2);
      expect(st.progressFor('https://m.example.com/b/1')!.chapterUrl, contains('/c3'));

      // load() 还原路径
      final st2 = AppState();
      await st2.load();
      final p = st2.progressFor('https://m.example.com/b/1');
      expect(p, isNotNull);
      expect(p!.chapterTitle, '第3话');
      expect(p.chapterIndex, 2);
      expect(p.chapterCount, 10);
    });

    test('同一本书重复保存只留最新', () async {
      final st = AppState();
      final book = Book.fromJson({'name': '测试书', 'bookUrl': 'https://m.example.com/b/2', 'sourceId': 's1'});
      await st.saveProgress(book, chapterUrl: 'c1', chapterTitle: '第1话', chapterIndex: 0, chapterCount: 5);
      await st.saveProgress(book, chapterUrl: 'c4', chapterTitle: '第4话', chapterIndex: 3, chapterCount: 5);
      expect(st.progressFor('https://m.example.com/b/2')!.chapterIndex, 3);
      expect(st.progress.length, 1);
    });
  });

  group('AppState 离线目录缓存', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('保存后可取回（load() 路径还原），空章节不写入', () async {
      final st = AppState();
      final book = Book.fromJson({'name': '缓存书', 'bookUrl': 'https://m.example.com/b/9', 'sourceId': 's1'});
      await st.saveDetailCache(book, []);
      expect(st.detailCacheFor('https://m.example.com/b/9'), isNull);

      await st.saveDetailCache(book, [
        Chapter(title: '第1话', url: 'https://m.example.com/b/9/c1'),
        Chapter(title: '第2话', url: 'https://m.example.com/b/9/c2'),
      ]);
      final hit = st.detailCacheFor('https://m.example.com/b/9');
      expect(hit, isNotNull);
      expect(hit!.chapters.length, 2);
      expect(hit.chapters.last.title, '第2话');

      final st2 = AppState();
      await st2.load();
      expect(st2.detailCacheFor('https://m.example.com/b/9')!.book.name, '缓存书');
    });
  });

  group('AppState 阅读器亮度', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('设置后持久化并在 load() 还原，下限截断', () async {
      final st = AppState();
      await st.setReaderBrightness(0.4);
      expect(st.readerBrightness, 0.4);

      await st.setReaderBrightness(0.01); // 低于下限
      expect(st.readerBrightness, 0.15);

      final st2 = AppState();
      await st2.load();
      expect(st2.readerBrightness, 0.15);
    });
  });
}
