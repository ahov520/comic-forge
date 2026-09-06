import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    final source = ComicSource.fromPpcatFlat({
      'bookSourceName': '测试源',
      'bookSourceUrl': 'https://example.com',
      'ruleSearchUrl': '/search?q=searchKey',
    });
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([source.toJson()]),
    });
    state = AppState();
    await state.load();
  });

  tearDown(() => state.dispose());

  test('去首尾空白、忽略空词；重复搜索置顶并保留其余顺序', () async {
    await state.recordSearch('  海贼王  ');
    await state.recordSearch('火影忍者');
    await state.recordSearch('ONE PIECE');
    await state.recordSearch(' \n\t ');
    await state.recordSearch('海贼王');

    expect(state.searchHistory, ['海贼王', 'ONE PIECE', '火影忍者']);
  });

  test('只保留最近 10 个不同词，重复搜索不会挤掉其他历史', () async {
    for (var i = 0; i < 12; i++) {
      await state.recordSearch('漫画$i');
    }
    expect(state.searchHistory, List.generate(10, (i) => '漫画${11 - i}'));

    await state.recordSearch('漫画5');
    expect(state.searchHistory, [
      '漫画5',
      '漫画11',
      '漫画10',
      '漫画9',
      '漫画8',
      '漫画7',
      '漫画6',
      '漫画4',
      '漫画3',
      '漫画2',
    ]);
  });

  test('新 AppState 从本地恢复历史、顺序和 10 条上限', () async {
    for (var i = 0; i < 12; i++) {
      await state.recordSearch('漫画$i');
    }
    await state.recordSearch('漫画5');

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.searchHistory, state.searchHistory);
    expect(restarted.searchHistory, hasLength(10));
  });

  test('清空历史持久化，重启后仍为空且不影响源库', () async {
    await state.recordSearch('海贼王');
    await state.recordSearch('火影忍者');
    await state.clearSearchHistory();

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(state.searchHistory, isEmpty);
    expect(restarted.searchHistory, isEmpty);
    expect(restarted.sources.single.name, '测试源');
  });

  test('快速连续记录并清空不会留下待写入的旧历史', () async {
    await Future.wait([
      state.recordSearch('海贼王'),
      state.recordSearch('火影忍者'),
      state.clearSearchHistory(),
    ]);

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.searchHistory, isEmpty);
  });

  test('恢复时过滤坏条目、空词、重复词和超出上限的旧词', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cf.searchHistory',
      jsonEncode([
        ' 海贼王 ',
        null,
        42,
        '海贼王',
        '',
        '  ',
        ...List.generate(12, (i) => '漫画$i'),
      ]),
    );

    await state.load();
    expect(state.searchHistory, ['海贼王', ...List.generate(9, (i) => '漫画$i')]);
  });

  for (final saved in [null, '{bad json', '{"query":"海贼王"}', 42]) {
    test('缺失或损坏的历史不影响启动：$saved', () async {
      SharedPreferences.setMockInitialValues({
        'cf.sources': jsonEncode(state.sources.map((s) => s.toJson()).toList()),
        'cf.searchHistory': ?saved,
      });

      await state.load();
      expect(state.searchHistory, isEmpty);
      expect(state.sources.single.name, '测试源');
    });
  }
}
