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
  }, timeout: const Timeout(Duration(minutes: 2)));
}
