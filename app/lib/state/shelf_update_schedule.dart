import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

enum ShelfUpdateInterval {
  hourly(1),
  sixHours(6),
  daily(24);

  const ShelfUpdateInterval(this.hours);
  final int hours;

  Duration get duration => Duration(hours: hours);
  String get label => '每 $hours 小时';
}

/// 自动检查偏好和最近一次尝试时间；手动检查也推迟下一次自动检查。
class ShelfUpdateSchedule extends ChangeNotifier {
  ShelfUpdateSchedule({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _key = 'cf.shelfUpdateSchedule';
  final DateTime Function() _now;
  bool _disposed = false;
  bool _enabled = false;
  ShelfUpdateInterval _interval = ShelfUpdateInterval.sixHours;
  DateTime? _lastCheckedAt;

  bool get enabled => _enabled;
  ShelfUpdateInterval get interval => _interval;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  Duration? get nextCheckIn {
    if (!_enabled) return null;
    final now = _now();
    final last = _lastCheckedAt;
    // 首次启用或设备时间回拨时检查一次，避免永远等待未来的时间戳。
    if (last == null || last.isAfter(now)) return Duration.zero;
    final remaining = last.add(_interval.duration).difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> load() async {
    _enabled = false;
    _interval = ShelfUpdateInterval.sixHours;
    _lastCheckedAt = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_key);
    if (raw is! String) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic>) return;
      _enabled = saved['enabled'] == true;
      _interval = ShelfUpdateInterval.values.firstWhere(
        (value) => value.hours == saved['intervalHours'],
        orElse: () => ShelfUpdateInterval.sixHours,
      );
      final at = saved['lastCheckedAt'];
      if (at is int && at > 0 && at <= 8640000000000000) {
        _lastCheckedAt = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
      }
    } on FormatException {
      // 损坏偏好恢复默认值，不影响书架和启动。
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setInterval(ShelfUpdateInterval value) async {
    if (_interval == value) return;
    _interval = value;
    notifyListeners();
    await _persist();
  }

  Future<void> recordCheck() async {
    _lastCheckedAt = _now().toUtc();
    await _persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringSafe(
      _key,
      jsonEncode({
        'enabled': _enabled,
        'intervalHours': _interval.hours,
        'lastCheckedAt': _lastCheckedAt?.millisecondsSinceEpoch,
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
