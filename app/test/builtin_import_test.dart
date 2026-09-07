import 'dart:convert';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/search_screen.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

const _tencentUrl = 'https://m.ac.qq.com';
const _searchPage = '''
<div class="comic-item">
  <a class="comic-link" href="/comic/123">
    <span class="comic-title">一人之下</span>
  </a>
  <span class="comic-tag">冒险</span>
  <span class="comic-update">第 10 话</span>
</div>
''';

class _RestoreState extends AppState {
  Future<int>? lastBuiltinImport;

  @override
  Future<int> importBuiltinSources() =>
      lastBuiltinImport = super.importBuiltinSources();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<ComicSource> snapshot;
  late _RestoreState state;

  setUpAll(() async {
    final text = await rootBundle.loadString('assets/store.json');
    final json = jsonDecode(text) as Map<String, dynamic>;
    snapshot = (json['sources'] as List)
        .cast<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat)
        .toList();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = _RestoreState();
    SourceService.instance.debugClearSwitchCache();
  });

  tearDown(() {
    SourceService.instance.debugRuntimeOverride = null;
    SourceService.instance.debugClearSwitchCache();
    state.dispose();
  });

  ComicSource tencent() => ComicSource.fromJson(
    snapshot.firstWhere((source) => source.id == _tencentUrl).toJson(),
  );

  Iterable<ComicSource> searchable(AppState value) => value.sources.where(
    (source) => source.enabled && source.rules.searchUrl.isNotEmpty,
  );

  test('冷启动自动导入，按源 ID 去重后持久化，重启仍可搜索', () async {
    await state.load();
    // 快照 493 条包含同地址的重复规则，源库按 ID 保留 483 个源。
    expect(state.sources, hasLength(483));
    expect(state.sources.map((source) => source.id).toSet(), hasLength(483));
    expect(searchable(state), hasLength(474));

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(
      restarted.sources.map((source) => source.toJson()),
      state.sources.map((source) => source.toJson()),
    );
    expect(searchable(restarted), hasLength(474));
    expect(
      restarted.sources
          .firstWhere((source) => source.id == _tencentUrl)
          .rules
          .chapterUrl,
      tencent().rules.chapterUrl,
    );
    expect(tencent().rules.chapterUrl, startsWith('tag.a@href#'));
    expect(await restarted.importBuiltinSources(), 0);
  });

  test('升级修复腾讯双字段旧章节链接，保留源设置并持久化', () async {
    final legacy = tencent()
      ..name = '我的腾讯源'
      ..enabled = false
      ..weight = 9
      ..lastError = '旧错误'
      ..lastFailedAt = 100
      ..lastOkAt = 50
      ..failCount = 3;
    legacy.rules.chapterUrl = 'id.btn_expandChapterList@href';
    await state.addSourceManual(legacy);

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(
      restarted.sources.single.rules.chapterUrl,
      tencent().rules.chapterUrl,
    );
    final expected = {
      ...legacy.toJson(),
      'rules': {
        ...legacy.rules.toJson(),
        'chapterUrl': tencent().rules.chapterUrl,
      },
    };
    expect(restarted.sources.single.toJson(), expected);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('cf.sources')!) as List;
    expect(saved.single, expected);

    final secondRestart = AppState();
    addTearDown(secondRestart.dispose);
    await secondRestart.load();
    expect(secondRestart.sources.single.toJson(), expected);
  });

  test('章节链接迁移保留手改规则及自定义源，恢复内置源也不覆盖', () async {
    final edited = tencent();
    edited.rules.chapterUrl = 'a.edited@href';
    final custom = ComicSource.fromJson({
      'id': 'custom',
      'name': '自定义源',
      'url': 'https://custom.example',
      'rules': {
        'chapterList': '.chapters li',
        'chapterUrl': 'id.btn_expandChapterList@href',
      },
    });
    await state.addSourceManual(edited);
    await state.addSourceManual(custom);

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.sources.map((source) => source.toJson()), [
      edited.toJson(),
      custom.toJson(),
    ]);
    await restarted.importBuiltinSources();
    expect(
      restarted.sources
          .firstWhere((source) => source.id == _tencentUrl)
          .toJson(),
      edited.toJson(),
    );
    expect(
      restarted.sources.firstWhere((source) => source.id == custom.id).toJson(),
      custom.toJson(),
    );
  });

  test('升级时修复已有内置源的搜索地址，不重新添加已删除源或修改自定义源', () async {
    final legacy = tencent()
      ..enabled = false
      ..weight = 9
      ..lastError = '旧错误'
      ..failCount = 3;
    legacy.rules.searchUrl = '';
    legacy.headers.clear();
    final custom = ComicSource.fromJson({
      'id': 'custom',
      'name': '自定义发现源',
      'url': 'https://custom.example',
      'rules': {'findUrl': '/discover', 'searchList': '.custom'},
    });
    await state.addSourceManual(legacy);
    await state.addSourceManual(custom);

    final restarted = AppState();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.sources, hasLength(2));
    final repaired = restarted.sources.first;
    expect(repaired.rules.searchUrl, tencent().rules.searchUrl);
    expect(repaired.headers, tencent().headers);
    expect(repaired.enabled, isFalse);
    expect(repaired.weight, 9);
    expect(repaired.lastError, '旧错误');
    expect(repaired.failCount, 3);
    expect(restarted.sources.last.toJson(), custom.toJson());

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('cf.sources')!) as List;
    expect(saved.first['rules']['searchUrl'], tencent().rules.searchUrl);
  });

  test('恢复补回缺失字段，保留已编辑规则、名称、启停、权重和健康记录', () async {
    final existing = tencent()
      ..name = '我的腾讯源'
      ..group = '收藏组'
      ..enabled = false
      ..weight = 7
      ..lastError = 'timeout'
      ..lastFailedAt = 100
      ..lastOkAt = 50
      ..failCount = 4;
    existing.rules
      ..searchUrl = ''
      ..searchList = '.edited-list';
    existing.headers.clear();
    await state.addSourceManual(existing);
    expect(await state.importBuiltinSources(), 483);
    final restored = state.sources.firstWhere((s) => s.id == _tencentUrl);
    expect(restored.name, '我的腾讯源');
    expect(restored.group, '收藏组');
    expect(restored.enabled, isFalse);
    expect(restored.weight, 7);
    expect(restored.lastError, 'timeout');
    expect(restored.lastFailedAt, 100);
    expect(restored.lastOkAt, 50);
    expect(restored.failCount, 4);
    expect(restored.rules.searchUrl, tencent().rules.searchUrl);
    expect(restored.rules.searchList, '.edited-list');
    expect(restored.headers, tencent().headers);
    expect(await state.importBuiltinSources(), 0);
    expect(state.sources, hasLength(483));
  });

  testWidgets('源页恢复入口导入快照并退出空态，重复恢复不重复添加', (tester) async {
    // 大资产解码在 isolate 中运行，先在真实异步环境完成加载。
    await tester.runAsync(() => rootBundle.loadString('assets/store.json'));
    await tester.pumpWidget(MaterialApp(home: SourceScreen(state: state)));
    expect(find.text('还没有源'), findsOneWidget);

    Future<void> restore() async {
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复内置源'));
        await tester.pumpAndSettle();
        expect(state.lastBuiltinImport, isNotNull);
        await state.lastBuiltinImport!.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();
    }

    await restore();
    expect(state.sources, hasLength(483));
    expect(find.text('源（483）'), findsOneWidget);
    expect(find.text('腾讯漫画（正版）'), findsOneWidget);
    expect(find.text('还没有源'), findsNothing);
    expect(find.text('已从内置快照恢复 483 个源'), findsOneWidget);
    await restore();
    expect(find.text('内置快照的源已全部在列'), findsOneWidget);
    expect(state.sources, hasLength(483));
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧版缺失搜索地址的快照升级后可聚合，单源失败不影响内置源结果', (tester) async {
    final legacy = <String, ComicSource>{};
    for (final source in snapshot) {
      legacy.putIfAbsent(source.id, () {
        final saved = ComicSource.fromJson(source.toJson());
        saved.rules.searchUrl = '';
        return saved;
      });
    }
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode(legacy.values.map((s) => s.toJson()).toList()),
    });
    await tester.runAsync(state.load);
    final attempted = <String>{};
    final fetcher = FakeFetcher((uri) {
      if (uri.host == 'm.ac.qq.com') {
        expect(uri.queryParameters['word'], '一人之下');
        return _searchPage;
      }
      throw FetchException('测试中的其它源离线');
    });
    SourceService.instance.debugRuntimeOverride = (source) {
      attempted.add(source.id);
      return SourceRuntime(source: source, fetcher: fetcher);
    };
    await tester.pumpWidget(MaterialApp(home: SearchScreen(state: state)));
    await tester.enterText(find.byType(TextField), '一人之下');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(attempted, hasLength(474));
    expect(find.text('一人之下'), findsWidgets);
    expect(find.text('源: 腾讯漫画（正版）'), findsOneWidget);
    expect(find.text('已聚合 474 个源 · 1 成功 473 失败'), findsOneWidget);
    expect(find.text('暂无可搜索的源'), findsNothing);
    expect(find.text('暂时无法连接漫画源'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
