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
}) =>
    ComicSource.fromPpcatFlat({
      'bookSourceName': name,
      'bookSourceUrl': url,
      'enabled': enabled,
      'ruleSearchUrl': '/search?q=searchKey',
    });

Future<void> _show(WidgetTester tester, AppState state) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SourceScreen(state: state))),
    );

void main() {
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });

  tearDown(() => state.dispose());

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
      expect(
        repoDisplayName('https://gitee.com/user/repo.git'),
        'user/repo',
      );
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
    state.repoLastRefresh[repo] =
        DateTime(2026, 9, 6).millisecondsSinceEpoch;
    await state.addSourceManual(_src());
    await state.addSourceManual(_src(
      name: '拾荒漫画',
      url: 'https://scavenge.example',
      enabled: false,
    ));
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

  testWidgets('从其它页推入时显示返回', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => SourceScreen(state: state)),
          ),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsNothing);
  });
}
