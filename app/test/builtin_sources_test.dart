import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置源快照可加载并解析（493 条）', () async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['sources'] as List).whereType<Map<String, dynamic>>().toList();
    expect(list.length, 493);

    final sources = list.map(ComicSource.fromPpcatFlat).toList();
    expect(sources.every((s) => s.name.isNotEmpty), isTrue);
    expect(sources.every((s) => s.url.startsWith('http')), isTrue);
    // 每条至少有搜索或发现规则可用
    final usable = sources
        .where((s) => s.rules.searchList.isNotEmpty || s.rules.findUrl.isNotEmpty)
        .length;
    expect(usable, greaterThan(400));

    // 快照几乎全部用 ruleSearchUrl；导入后必须落到嵌套 searchUrl，否则聚合搜索为 0 源。
    final withFlatSearch = list
        .where((m) =>
            (m['ruleSearchUrl'] is String && (m['ruleSearchUrl'] as String).isNotEmpty) ||
            (m['searchUrl'] is String && (m['searchUrl'] as String).isNotEmpty))
        .length;
    final withNestedSearch =
        sources.where((s) => s.rules.searchUrl.isNotEmpty).length;
    expect(withFlatSearch, greaterThan(400));
    expect(withNestedSearch, withFlatSearch);

    final withFlatHeaders = list.where((m) => m['headers'] is Map).length;
    final withNestedHeaders =
        sources.where((s) => s.headers.isNotEmpty).length;
    expect(withNestedHeaders, greaterThanOrEqualTo(withFlatHeaders));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('恢复内置：补空 searchUrl，保留启用/权重，不产生重复', () async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final incoming = (j['sources'] as List)
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat)
        .toList();
    final donor = incoming.firstWhere((s) => s.rules.searchUrl.isNotEmpty);

    final existing = [
      ComicSource(id: donor.id, name: '坏导入', enabled: false, weight: 11),
    ];

    final r = SourceCatalog.merge(
      existing,
      [...incoming, incoming.first],
      mode: SourceMergeMode.restoreBuiltins,
    );
    expect(r.repaired, 1);
    expect(existing.where((s) => s.id == donor.id).length, 1);
    expect(existing.firstWhere((s) => s.id == donor.id).enabled, isFalse);
    expect(existing.firstWhere((s) => s.id == donor.id).weight, 11);
    expect(existing.firstWhere((s) => s.id == donor.id).rules.searchUrl, isNotEmpty);
    expect(existing.length, SourceCatalog.dedupe(incoming).length);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
