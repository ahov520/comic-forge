import 'dart:convert';
import 'dart:io';

import 'package:engine/src/models/comic_source.dart';
import 'package:engine/src/source_catalog.dart';
import 'package:test/test.dart';

ComicSource src({
  required String id,
  String name = '',
  String searchUrl = 'https://m.example.com/search?q={{key}}',
  bool enabled = true,
  int weight = 0,
  Map<String, String>? headers,
}) {
  final s = ComicSource(
    id: id,
    name: name.isEmpty ? id : name,
    url: 'https://m.example.com',
    enabled: enabled,
    weight: weight,
    headers: headers,
  );
  s.rules.searchUrl = searchUrl;
  return s;
}

void main() {
  group('SourceCatalog.dedupe', () {
    test('同一 id 只留最后一条；空 id 用 url', () {
      final a = src(id: 'dup', name: 'A', searchUrl: '/a');
      final b = src(id: 'dup', name: 'B', searchUrl: '/b');
      final viaUrl = ComicSource(id: '', name: 'C', url: 'https://via.example');
      viaUrl.rules.searchUrl = '/c';
      final junk = ComicSource(id: '', name: '');

      final out = SourceCatalog.dedupe([a, b, viaUrl, junk]);
      expect(out.length, 2);
      expect(out.map((s) => s.id), containsAll(['dup', 'https://via.example']));
      expect(out.firstWhere((s) => s.id == 'dup').name, 'B');
    });
  });

  group('restoreBuiltins', () {
    test('补空 searchUrl / headers，保留启用与权重', () {
      final incoming = src(
        id: 'qq',
        name: '腾讯',
        searchUrl: '/search?word=searchKey',
        headers: {'User-Agent': 'Android'},
      );
      final existing = [
        ComicSource(id: 'qq', name: '腾讯旧', enabled: false, weight: 99),
      ];
      expect(existing.first.rules.searchUrl, isEmpty);

      final r = SourceCatalog.merge(
        existing,
        [incoming],
        mode: SourceMergeMode.restoreBuiltins,
      );
      expect(r.repaired, 1);
      expect(r.added, 0);
      expect(existing.length, 1);
      expect(existing.first.enabled, isFalse);
      expect(existing.first.weight, 99);
      expect(existing.first.rules.searchUrl, contains('searchKey'));
      expect(existing.first.headers['User-Agent'], 'Android');
    });

    test('已完好的源不覆盖，prefs 保持', () {
      final existing = [src(id: 'qq', name: '本地改过', enabled: false, weight: 3)];
      existing.first.rules.searchUrl = 'https://custom.example/s';
      final incoming = src(id: 'qq', name: '快照', searchUrl: '/official');

      final r = SourceCatalog.merge(
        existing,
        [incoming],
        mode: SourceMergeMode.restoreBuiltins,
      );
      expect(r.changed, 0);
      expect(existing.first.name, '本地改过');
      expect(existing.first.rules.searchUrl, 'https://custom.example/s');
      expect(existing.first.enabled, isFalse);
      expect(existing.first.weight, 3);
    });

    test('新源追加', () {
      final existing = [src(id: 'old')];
      final r = SourceCatalog.merge(
        existing,
        [src(id: 'new', name: '新')],
        mode: SourceMergeMode.restoreBuiltins,
      );
      expect(r.added, 1);
      expect(existing.map((s) => s.id), ['old', 'new']);
    });
  });

  group('subscribe', () {
    test('导入重复 id 不产生重复条目', () {
      final existing = <ComicSource>[];
      final r = SourceCatalog.merge(
        existing,
        [
          src(id: 'dup', name: 'A1', searchUrl: '/a1'),
          src(id: 'dup', name: 'A2', searchUrl: '/a2'),
        ],
        mode: SourceMergeMode.subscribe,
      );
      expect(existing.length, 1);
      expect(existing.first.name, 'A2');
      expect(r.skippedDupes, 1);
      expect(r.added, 1);
    });

    test('再订阅同一仓库：更新规则，保留启用/权重/健康', () {
      final existing = [src(id: 's1', enabled: false, weight: 8)];
      existing.first.health.markFailure('old-timeout');

      final incoming = src(id: 's1', name: '新规则', searchUrl: '/v2');
      final r = SourceCatalog.merge(
        existing,
        [incoming],
        mode: SourceMergeMode.subscribe,
      );
      expect(r.updated, 1);
      expect(existing.length, 1);
      expect(existing.first.enabled, isFalse);
      expect(existing.first.weight, 8);
      expect(existing.first.rules.searchUrl, '/v2');
      expect(existing.first.health.isUnhealthy, isTrue);
      expect(existing.first.health.lastError, 'old-timeout');
    });

    test('无 id/url/name 的坏条目丢弃', () {
      final existing = <ComicSource>[];
      final r = SourceCatalog.merge(
        existing,
        [ComicSource(id: '', name: '')],
        mode: SourceMergeMode.subscribe,
      );
      expect(existing, isEmpty);
      expect(r.skippedInvalid, 1);
      expect(r.added, 0);
    });
  });

  group('内置快照回归', () {
    test('恢复补空 searchUrl 且不擦除用户 prefs；二次恢复幂等', () {
      final snapshot = File('../store-snapshot/store.json');
      expect(snapshot.existsSync(), isTrue, reason: '需从 engine/ 目录运行 dart test');
      final j = jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
      final incoming = (j['sources'] as List)
          .whereType<Map<String, dynamic>>()
          .map(ComicSource.fromPpcatFlat)
          .toList();
      final donor = incoming.firstWhere((s) => s.rules.searchUrl.isNotEmpty);

      final existing = [
        ComicSource(
          id: donor.id,
          name: '旧坏导入',
          enabled: false,
          weight: 42,
        ),
      ];
      final first = SourceCatalog.merge(
        existing,
        incoming,
        mode: SourceMergeMode.restoreBuiltins,
      );
      final unique = SourceCatalog.dedupe(incoming);
      expect(first.repaired, 1);
      expect(first.added, unique.length - 1);
      expect(existing.length, unique.length);
      final repaired = existing.firstWhere((s) => s.id == donor.id);
      expect(repaired.enabled, isFalse);
      expect(repaired.weight, 42);
      expect(repaired.rules.searchUrl, isNotEmpty);

      repaired.enabled = false;
      repaired.weight = 7;
      final again = SourceCatalog.merge(
        existing,
        incoming,
        mode: SourceMergeMode.restoreBuiltins,
      );
      expect(again.repaired, 0);
      expect(again.added, 0);
      final againHit = existing.firstWhere((s) => s.id == donor.id);
      expect(againHit.enabled, isFalse);
      expect(againHit.weight, 7);
      expect(existing.length, unique.length);
    });
  });
}
