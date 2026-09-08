import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

/// 一组阅读器偏好快照：模式、亮度、音量键。不含进度或缩放手势。
class ReadingPrefPreset {
  const ReadingPrefPreset({
    required this.id,
    required this.name,
    required this.brightness,
    required this.mode,
    required this.volumeKeys,
    required this.at,
  });

  final String id;
  final String name;
  final double brightness;
  final String mode;
  final bool volumeKeys;
  final int at;

  bool get isPaged => mode == 'paged';

  String get summary {
    final modeLabel = isPaged ? '翻页' : '滚动';
    final volume = volumeKeys ? '音量键开' : '音量键关';
    return '$modeLabel · 亮度 ${(brightness * 100).round()}% · $volume';
  }

  bool matches({
    required double brightness,
    required String mode,
    required bool volumeKeys,
  }) {
    final normalized = mode == 'paged' ? 'paged' : 'scroll';
    return this.mode == normalized &&
        this.volumeKeys == volumeKeys &&
        (this.brightness * 100).round() ==
            (brightness.clamp(0.15, 1.0) * 100).round();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brightness': brightness,
    'mode': mode,
    'volumeKeys': volumeKeys,
    'at': at,
  };

  static ReadingPrefPreset? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final brightness = raw['brightness'];
    final mode = raw['mode'];
    final at = raw['at'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        brightness is! num ||
        !brightness.isFinite ||
        mode is! String ||
        at is! int ||
        at < 0) {
      return null;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.runes.length > ReadingPrefPresets.maxNameLength) {
      return null;
    }
    return ReadingPrefPreset(
      id: id,
      name: trimmed,
      brightness: brightness.toDouble().clamp(0.15, 1.0),
      mode: mode == 'paged' ? 'paged' : 'scroll',
      volumeKeys: raw['volumeKeys'] == true,
      at: at,
    );
  }
}

/// 命名阅读偏好预设。保存当前全局阅读设置，一点切换。
class ReadingPrefPresets extends ChangeNotifier {
  static const prefsKey = 'cf.readerPrefPresets';
  static const maxNameLength = 30;
  static const maxCount = 20;

  final List<ReadingPrefPreset> _presets = [];
  String? _activeId;
  Future<void>? _write;

  List<ReadingPrefPreset> get presets => List.unmodifiable(_presets);
  String? get lastAppliedId => _activeId;

  ReadingPrefPreset? byId(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// 优先返回上次应用且仍匹配当前偏好的预设，否则返回第一份匹配。
  ReadingPrefPreset? matching({
    required double brightness,
    required String mode,
    required bool volumeKeys,
  }) {
    final active = _activeId == null ? null : byId(_activeId!);
    if (active != null &&
        active.matches(
          brightness: brightness,
          mode: mode,
          volumeKeys: volumeKeys,
        )) {
      return active;
    }
    for (final preset in _presets) {
      if (preset.matches(
        brightness: brightness,
        mode: mode,
        volumeKeys: volumeKeys,
      )) {
        return preset;
      }
    }
    return null;
  }

  String? nameError(String name, {String? exceptId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '请输入预设名称';
    if (trimmed.runes.length > maxNameLength) return '预设名称最多 30 字';
    if (_presets.any(
      (preset) =>
          preset.id != exceptId &&
          preset.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return '预设名称已存在';
    }
    return null;
  }

  Future<void> load() async {
    await _write;
    _presets.clear();
    _activeId = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(prefsKey);
    if (raw is! String) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic>) return;
      _restore(saved);
    } on FormatException {
      // 坏预设不影响当前阅读偏好。
    }
  }

  Future<String> save({
    required String name,
    required double brightness,
    required String mode,
    required bool volumeKeys,
    int? at,
  }) async {
    final error = nameError(name);
    if (error != null) throw ArgumentError(error);
    if (_presets.length >= maxCount) {
      throw ArgumentError('最多保存 $maxCount 个预设');
    }
    final id = _newId();
    _presets.add(
      ReadingPrefPreset(
        id: id,
        name: name.trim(),
        brightness: brightness.clamp(0.15, 1.0),
        mode: mode == 'paged' ? 'paged' : 'scroll',
        volumeKeys: volumeKeys,
        at: at ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _activeId = id;
    await _persist();
    return id;
  }

  Future<void> rename(String id, String name) async {
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;
    final error = nameError(name, exceptId: id);
    if (error != null) throw ArgumentError(error);
    final current = _presets[index];
    _presets[index] = ReadingPrefPreset(
      id: current.id,
      name: name.trim(),
      brightness: current.brightness,
      mode: current.mode,
      volumeKeys: current.volumeKeys,
      at: current.at,
    );
    await _persist();
  }

  Future<void> updateValues(
    String id, {
    required double brightness,
    required String mode,
    required bool volumeKeys,
  }) async {
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) return;
    final current = _presets[index];
    _presets[index] = ReadingPrefPreset(
      id: current.id,
      name: current.name,
      brightness: brightness.clamp(0.15, 1.0),
      mode: mode == 'paged' ? 'paged' : 'scroll',
      volumeKeys: volumeKeys,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _activeId = id;
    await _persist();
  }

  Future<void> delete(String id) async {
    final before = _presets.length;
    _presets.removeWhere((preset) => preset.id == id);
    if (_presets.length == before) return;
    if (_activeId == id) _activeId = null;
    await _persist();
  }

  Future<void> markActive(String id) async {
    if (byId(id) == null || _activeId == id) return;
    _activeId = id;
    await _persist();
  }

  Map<String, dynamic> toBackupJson() => {
    'presets': _presets.map((preset) => preset.toJson()).toList(),
    if (_activeId != null) 'activeId': _activeId,
  };

  /// 备份导入：覆盖替换全部预设；合并时按 id 并集，名称冲突跳过备份项。
  Future<int> importBackup(
    Map<String, dynamic> json, {
    required bool overwrite,
  }) async {
    if (overwrite) {
      _presets.clear();
      _activeId = null;
    }
    var added = 0;
    _restore(json, merge: !overwrite, onAdded: () => added++);
    await _persist();
    return added;
  }

  void _restore(
    Map<String, dynamic> saved, {
    bool merge = false,
    VoidCallback? onAdded,
  }) {
    final ids = {for (final preset in _presets) preset.id};
    final names = {
      for (final preset in _presets) preset.name.toLowerCase(): preset.id,
    };
    final entries = saved['presets'];
    if (entries is List) {
      for (final entry in entries) {
        final preset = ReadingPrefPreset.tryParse(entry);
        if (preset == null ||
            ids.contains(preset.id) ||
            names.containsKey(preset.name.toLowerCase())) {
          continue;
        }
        if (_presets.length >= maxCount) break;
        ids.add(preset.id);
        names[preset.name.toLowerCase()] = preset.id;
        _presets.add(preset);
        onAdded?.call();
      }
    }
    final activeId = saved['activeId'];
    if (activeId is String && ids.contains(activeId)) {
      if (!merge || _activeId == null) _activeId = activeId;
    } else if (!merge) {
      _activeId = null;
    }
  }

  String _newId() {
    final base = 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    var id = base;
    for (var i = 1; _presets.any((preset) => preset.id == id); i++) {
      id = '$base-$i';
    }
    return id;
  }

  Future<void> _persist() {
    final saved = jsonEncode(toBackupJson());
    final write = (_write ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringSafe(prefsKey, saved);
    });
    _write = write;
    notifyListeners();
    return write;
  }
}
