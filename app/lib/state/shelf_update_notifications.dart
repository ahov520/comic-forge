import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

/// 更新通知开关，以及已经提示过的章节令牌（避免同一话重复通知）。
class ShelfUpdateNotifications extends ChangeNotifier {
  ShelfUpdateNotifications();

  static const _key = 'cf.shelfUpdateNotifications';
  bool _disposed = false;
  bool _enabled = false;
  final Map<String, String> _notifiedTokens = {};

  bool get enabled => _enabled;
  Map<String, String> get notifiedTokens => Map.unmodifiable(_notifiedTokens);

  Future<void> load() async {
    _enabled = false;
    _notifiedTokens.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_key);
    if (raw is! String) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic>) return;
      _enabled = saved['enabled'] == true;
      final tokens = saved['notifiedTokens'];
      if (tokens is Map<String, dynamic>) {
        tokens.forEach((key, value) {
          if (value is String && value.isNotEmpty) _notifiedTokens[key] = value;
        });
      }
    } on FormatException {
      // 损坏偏好恢复默认值，不影响书架检查。
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    if (!_disposed) notifyListeners();
    await _persist();
  }

  Future<void> markNotified(String key, String token) async {
    if (key.isEmpty || token.isEmpty) return;
    if (_notifiedTokens[key] == token) return;
    _notifiedTokens[key] = token;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringSafe(
      _key,
      jsonEncode({'enabled': _enabled, 'notifiedTokens': _notifiedTokens}),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
