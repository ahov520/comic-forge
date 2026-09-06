import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/settings_screen.dart';

void main() {
  testWidgets('深色模式开关切换 AppState', (tester) async {
    // 预置非空源库：跳过 load() 的内置快照导入（rootBundle 真实 IO 在
    // FakeAsync 测试区永不完成）
    const sources = '''[{"id":"https://m.example.com","name":"测试源","enabled":true,
      "rules":{"searchUrl":"/s?q={{key}}"}}]''';
    SharedPreferences.setMockInitialValues({'flutter.cf.sources': sources});
    final st = AppState();
    await st.load();
    expect(st.darkMode, true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SettingsScreen(state: st)),
    ));
    await tester.pump();
    await tester.tap(find.text('深色模式'));
    await tester.pump();
    expect(st.darkMode, false, reason: '点按开关应切换深色模式');
  });
}
