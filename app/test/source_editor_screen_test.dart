import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/source_editor_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _open(
  WidgetTester tester,
  AppState state,
  ComicSource source,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SourceEditorScreen(state: state, source: source),
            ),
          ),
          child: const Text('打开编辑器'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;
  late ComicSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'editable-source',
      'name': '原源',
      'url': 'https://old.example.com',
      'enabled': false,
      'weight': 12,
      'lastError': 'HTTP 503',
      'lastFailedAt': 200,
      'failCount': 4,
      'lastOkAt': 100,
      'rules': {
        'searchUrl': '/search?q=searchKey',
        'exploreUrl': '推荐::/featured',
        'findList': '.discovery',
        'bookName': 'h1@text',
        'bookAuthor': '.author@text',
        'chapterUrlNext': '.next@href',
        'contentInit': '.pages',
      },
    });
    await state.addSourceManual(source);
  });

  tearDown(() => state.dispose());

  testWidgets('保存名称和地址后重启仍保留隐藏规则、启停与健康记录', (tester) async {
    await _open(tester, state, source);
    await tester.enterText(_field('名称 *'), '改名源');
    await tester.enterText(
      _field('源地址 *（http/https 公网）'),
      'https://new.example.com',
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditorScreen), findsNothing);

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    final saved = restored.sources.single;
    expect(saved.id, source.id);
    expect(saved.name, '改名源');
    expect(saved.url, 'https://new.example.com');
    expect(saved.enabled, isFalse);
    expect(saved.weight, 12);
    expect(saved.lastError, 'HTTP 503');
    expect(saved.lastFailedAt, 200);
    expect(saved.failCount, 4);
    expect(saved.lastOkAt, 100);
    expect(saved.rules.bookName, 'h1@text');
    expect(saved.rules.bookAuthor, '.author@text');
    expect(saved.rules.chapterUrlNext, '.next@href');
    expect(saved.rules.contentInit, '.pages');
    expect(saved.rules.findList, '.discovery');
    expect(saved.rules.findUrl, '推荐::/featured');
    expect(source.name, '原源');
    expect(source.rules.exploreUrl, '推荐::/featured');
    expect(tester.takeException(), isNull);
  });

  testWidgets('发现旧别名预填到表单，用户可以显式清空', (tester) async {
    await _open(tester, state, source);
    await tester.tap(find.text('基本信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现与详情'));
    await tester.pumpAndSettle();
    final entry = _field('发现入口（名称::url，每行一条）');
    expect(tester.widget<TextField>(entry).controller!.text, '推荐::/featured');
    await tester.enterText(entry, '');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(state.sources.single.rules.findUrl, isEmpty);
    expect(state.sources.single.rules.exploreUrl, isEmpty);
    expect(state.sources.single.rules.findList, '.discovery');
    expect(source.rules.exploreUrl, '推荐::/featured');
    expect(tester.takeException(), isNull);
  });
}
