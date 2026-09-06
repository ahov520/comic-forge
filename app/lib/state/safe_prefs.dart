import 'package:shared_preferences/shared_preferences.dart';

/// 持久化写入容错：web 端 localStorage 配额超限（如 493 源快照）等失败
/// 不应让 App 崩溃/白屏——内存态照常工作，仅该次变更重启后丢失。
extension SafePrefs on SharedPreferences {
  Future<bool> setStringSafe(String key, String value) async {
    try {
      return await setString(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setBoolSafe(String key, bool value) async {
    try {
      return await setBool(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDoubleSafe(String key, double value) async {
    try {
      return await setDouble(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeSafe(String key) async {
    try {
      return await remove(key);
    } catch (_) {
      return false;
    }
  }
}
