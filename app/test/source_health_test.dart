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
      await st.reportSourceHealth(const [], {'no-such-id': 'err'});
      await st.reportSourceHealth(['no-such-id'], const {});
      expect(st.sources.first.failCount, 0);
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
      expect(fixed.rules.searchUrl, isNotEmpty, reason: '内置快照应补回 searchUrl');
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
}
