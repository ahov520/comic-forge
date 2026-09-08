import 'dart:convert';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ComicSource _source() => ComicSource.fromJson({
  'id': 'a',
  'name': '测试源',
  'url': 'https://ok.example',
  'rules': {'searchUrl': '/s'},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([_source().toJson()]),
    });
    SourceService.instance.debugResetNetworkPolicy();
  });

  tearDown(SourceService.instance.debugResetNetworkPolicy);

  test('增删域名会规范化、去重并跨重启恢复', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.load();
    expect(await state.addBlockedDomain('https://EVIL.com/path'), isTrue);
    expect(await state.addBlockedDomain('*.evil.com'), isFalse);
    expect(await state.addBlockedDomain('not a host'), isFalse);
    expect(await state.addBlockedDomain('cdn.tracker.net'), isTrue);
    expect(state.blockedDomains, ['cdn.tracker.net', 'evil.com']);
    expect(
      SourceService.instance.networkPolicy.isBlocked('https://www.evil.com/a'),
      isTrue,
    );

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.blockedDomains, ['cdn.tracker.net', 'evil.com']);
    expect(
      await restored.removeBlockedDomain('https://cdn.tracker.net/x'),
      isTrue,
    );
    expect(restored.blockedDomains, ['evil.com']);

    await state.load();
    expect(state.blockedDomains, ['evil.com']);
  });

  test('损坏的黑名单配置回退为空', () async {
    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([_source().toJson()]),
      'cf.domainBlocklist': '{bad',
    });
    final state = AppState();
    addTearDown(state.dispose);
    await state.load();
    expect(state.blockedDomains, isEmpty);
  });
}
