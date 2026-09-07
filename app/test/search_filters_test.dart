import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/search_filters.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ComicSource source(
    String id, {
    int failures = 0,
    bool enabled = true,
    bool search = true,
  }) => ComicSource(
    id: id,
    enabled: enabled,
    rules: RuleSet()..searchUrl = search ? '/search' : '',
  )..failCount = failures;

  test('按源与健康共同限定实际搜索范围，默认仍包含未检测源', () {
    final sources = [
      source('fresh'),
      source('two', failures: 2),
      source('bad', failures: 3),
      source('disabled', enabled: false),
      source('no-search', search: false),
    ];
    expect(sources.where(SearchFilters().accepts).map((s) => s.id), [
      'fresh',
      'two',
      'bad',
    ]);
    expect(
      sources.where(SearchFilters(onlyHealthy: true).accepts).map((s) => s.id),
      ['fresh', 'two'],
    );
    expect(
      sources
          .where(
            SearchFilters(onlyHealthy: true, sourceIds: {'two', 'bad'}).accepts,
          )
          .map((s) => s.id),
      ['two'],
    );
    expect(sources.where(SearchFilters(sourceIds: {}).accepts), isEmpty);
    expect(
      sources.where(SearchFilters(sourceIds: {'missing'}).accepts),
      isEmpty,
    );
  });

  test('筛选不可被调用者修改，源顺序不影响相等比较，空选择区别于全部', () {
    final ids = {'a', 'b'};
    final filters = SearchFilters(sourceIds: ids);
    ids.clear();
    expect(filters.sourceIds, {'a', 'b'});
    expect(() => filters.sourceIds!.clear(), throwsUnsupportedError);
    expect(filters, SearchFilters(sourceIds: {'b', 'a'}));
    expect(filters.hashCode, SearchFilters(sourceIds: {'b', 'a'}).hashCode);
    expect(SearchFilters(sourceIds: {}), isNot(SearchFilters()));
  });

  test('本地恢复组合筛选，重置持久化且不会改变源启停', () async {
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([source('a').toJson()]),
    });
    final state = AppState();
    addTearDown(state.dispose);
    await state.load();
    await state.setSearchFilters(
      SearchFilters(onlyHealthy: true, sourceIds: {'a'}),
    );
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.searchFilters, state.searchFilters);
    expect(restored.sources.single.enabled, isTrue);
    await restored.setSearchFilters(SearchFilters(sourceIds: {}));
    await state.load();
    expect(state.searchFilters.sourceIds, isEmpty);
    await state.setSearchFilters(SearchFilters());
    await restored.load();
    expect(restored.searchFilters.isActive, isFalse);
  });

  for (final saved in [
    null,
    42,
    '{bad',
    '[]',
    '{"onlyHealthy":42,"sourceIds":"bad"}',
  ]) {
    test('缺失或损坏过滤配置回退全部源：$saved', () async {
      SharedPreferences.setMockInitialValues({
        'cf.sources': jsonEncode([source('a').toJson()]),
        'cf.searchFilters': ?saved,
      });
      final state = AppState();
      addTearDown(state.dispose);
      await state.load();
      expect(state.searchFilters, SearchFilters());
    });
  }
}
