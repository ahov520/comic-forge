import 'dart:convert';

import 'package:comic_forge/state/shelf_update_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late ShelfUpdateSchedule schedule;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 8, 12);
    schedule = ShelfUpdateSchedule(now: () => now);
  });
  tearDown(() => schedule.dispose());

  test('默认关闭；开关、间隔与最近尝试时间跨重启保留', () async {
    await schedule.load();
    expect(schedule.enabled, isFalse);
    expect(schedule.interval, ShelfUpdateInterval.sixHours);
    expect(schedule.nextCheckIn, isNull);
    await schedule.setEnabled(true);
    expect(schedule.nextCheckIn, Duration.zero);
    await schedule.setInterval(ShelfUpdateInterval.daily);
    await schedule.recordCheck();
    now = now.add(const Duration(hours: 2));

    final restored = ShelfUpdateSchedule(now: () => now);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.interval, ShelfUpdateInterval.daily);
    expect(restored.lastCheckedAt, schedule.lastCheckedAt);
    expect(restored.nextCheckIn, const Duration(hours: 22));
    await restored.setEnabled(false);
    await schedule.load();
    expect(schedule.enabled, isFalse);
    expect(schedule.interval, ShelfUpdateInterval.daily);
  });

  test('精确到期间隔、修改间隔和时钟回拨均能重新计算', () async {
    await schedule.setEnabled(true);
    await schedule.recordCheck();
    final checked = now;
    now = checked.add(const Duration(hours: 6) - const Duration(seconds: 1));
    expect(schedule.nextCheckIn, const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    expect(schedule.nextCheckIn, Duration.zero);
    await schedule.setInterval(ShelfUpdateInterval.daily);
    expect(schedule.nextCheckIn, const Duration(hours: 18));
    await schedule.setInterval(ShelfUpdateInterval.hourly);
    expect(schedule.nextCheckIn, Duration.zero);
    now = checked.subtract(const Duration(hours: 1));
    expect(schedule.nextCheckIn, Duration.zero);
    await schedule.recordCheck();
    expect(schedule.nextCheckIn, const Duration(hours: 1));
  });

  for (final raw in [123, '{broken', '[]', 'null']) {
    test('损坏偏好使用默认值：$raw', () async {
      SharedPreferences.setMockInitialValues({'cf.shelfUpdateSchedule': raw});
      await schedule.load();
      expect(schedule.enabled, isFalse);
      expect(schedule.interval, ShelfUpdateInterval.sixHours);
      expect(schedule.lastCheckedAt, isNull);
    });
  }

  test('非法间隔和时间戳不影响有效开关，未来时间戳不会阻止检查', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final at in [-1, 'yesterday', 9000000000000000]) {
      await prefs.setString(
        'cf.shelfUpdateSchedule',
        jsonEncode({'enabled': true, 'intervalHours': 0, 'lastCheckedAt': at}),
      );
      await schedule.load();
      expect(schedule.enabled, isTrue);
      expect(schedule.interval, ShelfUpdateInterval.sixHours);
      expect(schedule.lastCheckedAt, isNull);
      expect(schedule.nextCheckIn, Duration.zero);
    }
    await prefs.setString(
      'cf.shelfUpdateSchedule',
      jsonEncode({
        'enabled': true,
        'intervalHours': 1,
        'lastCheckedAt': now
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      }),
    );
    await schedule.load();
    expect(schedule.nextCheckIn, Duration.zero);
  });
}
