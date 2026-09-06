import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/source_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('源列表标记不可用源，开关可禁用', (tester) async {
    final state = AppState();
    final dead = ComicSource(id: 'dead', name: '死源', url: 'https://dead.example');
    dead.health.markFailure('HTTP 403');
    final ok = ComicSource(id: 'ok', name: '好源', url: 'https://ok.example');
    ok.health.markSuccess();
    final off = ComicSource(id: 'off', name: '关源', enabled: false);
    state.sources.addAll([dead, ok, off]);

    await tester.pumpWidget(MaterialApp(home: SourceScreen(state: state)));

    expect(find.textContaining('启用 2'), findsOneWidget);
    expect(find.textContaining('异常 1'), findsOneWidget);
    expect(find.text('死源'), findsOneWidget);
    expect(find.textContaining('不可用'), findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.textContaining('已禁用'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(state.sources.firstWhere((s) => s.id == 'dead').enabled, isFalse);
  });
}
