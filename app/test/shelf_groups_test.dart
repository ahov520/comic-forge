import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_groups.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  final book = Book(name: '分组漫画', bookUrl: '/book', sourceId: 'groups');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(
      ComicSource.fromJson({
        'id': 'groups',
        'name': '测试源',
        'url': 'https://groups.example',
      }),
    );
    await state.toggleShelf(book);
  });

  tearDown(() => state.dispose());

  Future<AppState> restart() async {
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    return restored;
  }

  test('多分组、重命名和筛选跨重启保留，未分组仅包含未分配漫画', () async {
    final groups = state.shelfGroups;
    final a = await groups.create('  追更  ');
    final b = await groups.create('收藏');
    await state.assignShelfGroups(book, [a, a, b, 'missing']);
    await groups.rename(a, '每日追更');
    await groups.selectFilter(a);
    expect(groups.matches(book.bookUrl), isTrue);
    expect(groups.matches('/other'), isFalse);

    final restored = await restart();
    expect(restored.shelfGroups.groups.map((g) => g.name), ['每日追更', '收藏']);
    expect(restored.shelfGroups.groupsFor(book.bookUrl), {a, b});
    expect(restored.shelfGroups.filter, a);
    await restored.shelfGroups.selectFilter('');
    expect(restored.shelfGroups.matches(book.bookUrl), isFalse);
    expect(restored.shelfGroups.matches('/other'), isTrue);
    await restored.assignShelfGroups(book, []);
    expect(restored.shelfGroups.matches(book.bookUrl), isTrue);
  });

  test('空名、重复名、保留名称和超长名被拒绝，重命名自己合法', () async {
    final groups = state.shelfGroups;
    final id = await groups.create('Favorites');
    for (final name in [
      '',
      ' \n ',
      'favorites',
      ' Favorites ',
      '未分组',
      '全部分组',
      '字' * 31,
    ]) {
      await expectLater(groups.create(name), throwsArgumentError);
    }
    await groups.rename(id, ' Favorites ');
    final other = await groups.create('追更');
    await expectLater(groups.rename(other, 'favorites'), throwsArgumentError);
    expect(groups.groups.map((g) => g.name), ['Favorites', '追更']);
  });

  test('删除选中分组恢复全部且保留其它关联、书架、进度与历史', () async {
    final groups = state.shelfGroups;
    final a = await groups.create('追更');
    final b = await groups.create('喜爱');
    await state.assignShelfGroups(book, [a, b]);
    await state.saveProgress(
      book,
      chapterUrl: '/c1',
      chapterTitle: '第一话',
      chapterIndex: 0,
      chapterCount: 3,
    );
    final progress = state.progressFor(book.bookUrl)!.toJson();
    await groups.selectFilter(a);
    await groups.delete(a);
    expect(groups.filter, isNull);
    expect(groups.groupsFor(book.bookUrl), {b});
    await groups.delete(b);
    final restored = await restart();
    expect(restored.shelfGroups.groups, isEmpty);
    expect(restored.shelfGroups.groupsFor(book.bookUrl), isEmpty);
    expect(restored.inShelf(book), isTrue);
    expect(restored.progressFor(book.bookUrl)!.toJson(), progress);
    expect(restored.readingHistory, hasLength(1));
  });

  test('取消收藏清理关联，未收藏漫画不能分组，重新收藏归入未分组', () async {
    final id = await state.shelfGroups.create('追更');
    await state.assignShelfGroups(book, [id]);
    await state.toggleShelf(book);
    await state.assignShelfGroups(book, [id]);
    expect(state.shelfGroups.groupsFor(book.bookUrl), isEmpty);
    await state.toggleShelf(book);
    expect((await restart()).shelfGroups.groupsFor(book.bookUrl), isEmpty);
  });

  test('连续写入和删除串行持久化，重启不会恢复旧关联', () async {
    final a = await state.shelfGroups.create('A');
    final b = await state.shelfGroups.create('B');
    await Future.wait([
      state.assignShelfGroups(book, [a]),
      state.assignShelfGroups(book, [a, b]),
      state.shelfGroups.selectFilter(a),
      state.shelfGroups.delete(a),
    ]);
    final restored = await restart();
    expect(restored.shelfGroups.groupsFor(book.bookUrl), {b});
    expect(restored.shelfGroups.filter, isNull);
  });

  test('恢复过滤坏条目、重复分组、失效关联和不存在的筛选', () async {
    await (await SharedPreferences.getInstance()).setString(
      ShelfGroups.prefsKey,
      jsonEncode({
        'groups': [
          {'id': 'one', 'name': '  保留  '},
          {'id': 'one', 'name': '重复 ID'},
          {'id': 'two', 'name': '保留'},
          {'id': '', 'name': '坏 ID'},
          {'id': 'three', 'name': 42},
          null,
          {'id': 'four', 'name': '另一个'},
        ],
        'assignments': {
          '/book': ['one', 'one', 'missing', 42],
          '/removed': ['four'],
        },
        'filter': 'missing',
      }),
    );
    final restored = await restart();
    expect(restored.shelfGroups.groups.map((g) => g.id), ['one', 'four']);
    expect(restored.shelfGroups.groupsFor('/book'), {'one'});
    expect(restored.shelfGroups.groupsFor('/removed'), isEmpty);
    expect(restored.shelfGroups.filter, isNull);
  });

  for (final saved in [null, 42, '{broken', '[]']) {
    test('缺失或损坏分组不影响旧书架：$saved', () async {
      final prefs = await SharedPreferences.getInstance();
      if (saved is String) await prefs.setString(ShelfGroups.prefsKey, saved);
      if (saved is int) await prefs.setInt(ShelfGroups.prefsKey, saved);
      final restored = await restart();
      expect(restored.inShelf(book), isTrue);
      expect(restored.shelfGroups.groups, isEmpty);
      expect(restored.shelfGroups.matches(book.bookUrl), isTrue);
    });
  }
}
