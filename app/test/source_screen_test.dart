import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ComicSource _src({
  String name = '示例漫画源 A',
  String url = 'https://example.com',
  bool enabled = true,
}) => ComicSource.fromPpcatFlat({
  'bookSourceName': name,
  'bookSourceUrl': url,
  'enabled': enabled,
  'ruleSearchUrl': '/search?q=searchKey',
});

Future<void> _show(WidgetTester tester, AppState state) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SourceScreen(state: state)),
  ),
);

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });

  tearDown(() => state.dispose());

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字号空仓库可滚动，返回与订阅入口可操作：${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await state.addRepoSubscribed(
        'https://github.com/example/long-repository-name',
        const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SourceScreen(state: state)),
              ),
              child: const Text('打开源管理'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开源管理'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('仓库里还没有源'));
      await tester.tap(find.text('＋ 订阅仓库'));
      await tester.pumpAndSettle();
      expect(find.text('订阅源仓库'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  group('repoDisplayName / repoSyncLabel', () {
    test('仓库 URL 收成 user/repo 短名', () {
      expect(
        repoDisplayName('https://github.com/AcgLibrary/ppcat_store'),
        'AcgLibrary/ppcat_store',
      );
      expect(
        repoDisplayName('github.com/AcgLibrary/ppcat_store'),
        'AcgLibrary/ppcat_store',
      );
      expect(repoDisplayName('https://gitee.com/user/repo.git'), 'user/repo');
    });

    test('同步时间格式化为 MM-DD', () {
      expect(repoSyncLabel(null), '尚未检查更新');
      expect(
        repoSyncLabel(DateTime(2026, 9, 6).millisecondsSinceEpoch),
        '上次同步 09-06',
      );
    });
  });

  testWidgets('空源页对齐设计稿：大标题、订阅、粘贴导入、空态', (tester) async {
    await _show(tester, state);

    expect(find.text('源'), findsOneWidget);
    expect(find.text('＋ 订阅仓库'), findsOneWidget);
    expect(find.text('粘贴导入单个源 JSON'), findsOneWidget);
    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.text('还没有源'), findsOneWidget);
    expect(find.text('订阅仓库'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('返回'), findsNothing);
  });

  testWidgets('点订阅仓库弹出输入框', (tester) async {
    await _show(tester, state);
    await tester.tap(find.text('＋ 订阅仓库'));
    await tester.pumpAndSettle();
    expect(find.text('订阅源仓库'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('仓库卡片显示短名与同步信息，源行带开关可启停', (tester) async {
    const repo = 'https://github.com/AcgLibrary/ppcat_store';
    await state.addRepoSubscribed(repo, const []);
    state.repoLastRefresh[repo] = DateTime(2026, 9, 6).millisecondsSinceEpoch;
    await state.addSourceManual(_src());
    await state.addSourceManual(
      _src(name: '拾荒漫画', url: 'https://scavenge.example', enabled: false),
    );
    await _show(tester, state);

    expect(find.text('已订阅仓库'), findsOneWidget);
    expect(find.text('AcgLibrary/ppcat_store'), findsOneWidget);
    expect(find.text('上次同步 09-06'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);

    expect(find.text('示例漫画源 A'), findsOneWidget);
    expect(find.text('拾荒漫画'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.text('长按删除 · 开关控制聚合范围'), findsOneWidget);
    expect(find.text('粘贴导入单个源 JSON'), findsOneWidget);

    final enabledSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(enabledSwitch.value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(state.sources.first.enabled, isFalse);
  });

  testWidgets('仓库卡间距为 10px，末卡到源分组不叠加外边距', (tester) async {
    tester.view.physicalSize = const Size(340, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.addRepoSubscribed('https://github.com/team/first', const []);
    await state.addRepoSubscribed('https://github.com/team/second', const []);
    await state.addSourceManual(_src());
    await _show(tester, state);

    Rect cardBounds(int index) => tester.getRect(
      find
          .descendant(
            of: find.byType(Card).at(index),
            matching: find.byType(Material),
          )
          .first,
    );
    final first = cardBounds(0);
    final last = cardBounds(1);
    final sourceLabel = tester.getRect(find.text('源（1）'));
    expect(last.top - first.bottom, closeTo(10, 0.01));
    expect(sourceLabel.top - last.bottom, closeTo(14, 0.01));
    expect(sourceLabel.left, last.left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('相同错误连续回报会即时更新次数与失效标记，重启后仍保留', (tester) async {
    final source = _src();
    await state.addSourceManual(source);
    await _show(tester, state);
    for (var count = 1; count <= 3; count++) {
      await state.reportSourceHealth(const [], {source.id: 'timeout'});
      await tester.pumpAndSettle();
      expect(find.textContaining('最近失败($count)'), findsOneWidget);
    }
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.sources.single.failCount, 3);
    expect(restored.sources.single.isUnhealthy, isTrue);

    await state.reportSourceHealth([source.id], const {});
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('最近失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从其它页推入时显示返回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => SourceScreen(state: state)),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsNothing);
  });
}
