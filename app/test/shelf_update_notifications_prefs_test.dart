import 'dart:convert';

import 'package:comic_forge/state/shelf_update_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShelfUpdateNotifications prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = ShelfUpdateNotifications();
  });
  tearDown(() => prefs.dispose());

  test('默认关闭；开关与已通知令牌跨重启保留', () async {
    await prefs.load();
    expect(prefs.enabled, isFalse);
    expect(prefs.notifiedTokens, isEmpty);
    await prefs.setEnabled(true);
    await prefs.markNotified('["src","https://a"]', 'token-1');

    final restored = ShelfUpdateNotifications();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.notifiedTokens, {'["src","https://a"]': 'token-1'});
    await restored.setEnabled(false);
    await prefs.load();
    expect(prefs.enabled, isFalse);
    expect(prefs.notifiedTokens, {'["src","https://a"]': 'token-1'});
  });

  for (final raw in [123, '{broken', '[]', 'null']) {
    test('损坏偏好使用默认值：$raw', () async {
      SharedPreferences.setMockInitialValues({
        'cf.shelfUpdateNotifications': raw,
      });
      await prefs.load();
      expect(prefs.enabled, isFalse);
      expect(prefs.notifiedTokens, isEmpty);
    });
  }

  test('非法令牌被丢弃，开关仍可恢复', () async {
    final store = await SharedPreferences.getInstance();
    await store.setString(
      'cf.shelfUpdateNotifications',
      jsonEncode({
        'enabled': true,
        'notifiedTokens': {'ok': 'token', 'empty': '', 'number': 1},
      }),
    );
    await prefs.load();
    expect(prefs.enabled, isTrue);
    expect(prefs.notifiedTokens, {'ok': 'token'});
  });
}
