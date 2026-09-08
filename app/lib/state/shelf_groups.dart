import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

class ShelfGroup {
  const ShelfGroup({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};
}

/// 分组与漫画多对多关联；重命名保留 ID，删除分组不删除漫画。
class ShelfGroups extends ChangeNotifier {
  static const prefsKey = 'cf.shelfGroups';
  static const maxNameLength = 30;
  final List<ShelfGroup> _groups = [];
  final Map<String, Set<String>> _assignments = {};
  Future<void>? _write;
  String? _filter;

  List<ShelfGroup> get groups => List.unmodifiable(_groups);
  Iterable<String> get assignedBookUrls => _assignments.keys;

  /// null = 全部分组，空串 = 未分组，其它值为分组 ID。
  String? get filter => _filter;

  Set<String> groupsFor(String bookUrl) =>
      Set.unmodifiable(_assignments[bookUrl] ?? const <String>{});

  bool matches(String bookUrl) => switch (_filter) {
    null => true,
    '' => groupsFor(bookUrl).isEmpty,
    final id => groupsFor(bookUrl).contains(id),
  };

  String? nameError(String name, {String? exceptId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '请输入分组名称';
    if (trimmed.runes.length > maxNameLength) return '分组名称最多 30 字';
    if (const ['全部分组', '未分组'].contains(trimmed)) return '请使用其他分组名称';
    if (_groups.any(
      (g) => g.id != exceptId && g.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return '分组名称已存在';
    }
    return null;
  }

  Future<void> load(Iterable<String> bookUrls) async {
    await _write;
    _groups.clear();
    _assignments.clear();
    _filter = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(prefsKey);
    if (raw is! String) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic>) return;
      final ids = <String>{};
      final entries = saved['groups'];
      if (entries is List) {
        for (final entry in entries) {
          if (entry is! Map<String, dynamic>) continue;
          final id = entry['id'];
          final name = entry['name'];
          if (id is! String ||
              id == 'all' ||
              id.trim().isEmpty ||
              ids.contains(id) ||
              name is! String ||
              nameError(name) != null) {
            continue;
          }
          ids.add(id);
          _groups.add(ShelfGroup(id: id, name: name.trim()));
        }
      }
      final assignments = saved['assignments'];
      if (assignments is Map<String, dynamic>) {
        for (final url in bookUrls) {
          final values = assignments[url];
          if (values is! List) continue;
          final valid = values.whereType<String>().where(ids.contains).toSet();
          if (valid.isNotEmpty) _assignments[url] = valid;
        }
      }
      final filter = saved['filter'];
      if (filter is String && (filter.isEmpty || ids.contains(filter))) {
        _filter = filter;
      }
    } on FormatException {
      // 坏分组数据不影响书架或阅读进度。
    }
  }

  Future<String> create(String name) async {
    final error = nameError(name);
    if (error != null) throw ArgumentError(error);
    final base = 'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    var id = base;
    for (var i = 1; _groups.any((group) => group.id == id); i++) {
      id = '$base-$i';
    }
    _groups.add(ShelfGroup(id: id, name: name.trim()));
    await _persist();
    return id;
  }

  Future<void> rename(String id, String name) async {
    final index = _groups.indexWhere((group) => group.id == id);
    if (index < 0) return;
    final error = nameError(name, exceptId: id);
    if (error != null) throw ArgumentError(error);
    _groups[index] = ShelfGroup(id: id, name: name.trim());
    await _persist();
  }

  Future<void> delete(String id) async {
    _groups.removeWhere((group) => group.id == id);
    for (final ids in _assignments.values) {
      ids.remove(id);
    }
    _assignments.removeWhere((_, ids) => ids.isEmpty);
    if (_filter == id) _filter = null;
    await _persist();
  }

  Future<void> assign(String bookUrl, Iterable<String> groupIds) =>
      assignMany([bookUrl], groupIds: groupIds);

  /// [union] 为 true 时把分组追加到已有关联；否则整表替换（空集合即移出全部分组）。
  Future<void> assignMany(
    Iterable<String> bookUrls, {
    required Iterable<String> groupIds,
    bool union = false,
  }) async {
    final existing = _groups.map((group) => group.id).toSet();
    final ids = groupIds.where(existing.contains).toSet();
    var changed = false;
    for (final url in bookUrls) {
      if (url.isEmpty) continue;
      if (union) {
        if (ids.isEmpty) continue;
        final current = _assignments.putIfAbsent(url, () => <String>{});
        final before = current.length;
        current.addAll(ids);
        if (current.length != before) changed = true;
      } else if (!setEquals(_assignments[url] ?? const <String>{}, ids)) {
        if (ids.isEmpty) {
          _assignments.remove(url);
        } else {
          _assignments[url] = Set<String>.of(ids);
        }
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  Future<void> removeBook(String bookUrl) => removeBooks([bookUrl]);

  Future<void> removeBooks(Iterable<String> bookUrls) async {
    var changed = false;
    for (final url in bookUrls) {
      if (_assignments.remove(url) != null) changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> selectFilter(String? id) async {
    if (id != null &&
        id.isNotEmpty &&
        !_groups.any((group) => group.id == id)) {
      return;
    }
    if (_filter == id) return;
    _filter = id;
    await _persist();
  }

  Map<String, dynamic> toBackupJson() => {
    'groups': _groups.map((group) => group.toJson()).toList(),
    'assignments': _assignments.map((url, ids) => MapEntry(url, ids.toList())),
  };

  /// 备份导入：覆盖替换分组与关联；合并时按 id 并集，名称冲突跳过备份项。
  Future<int> importBackup(
    Map<String, dynamic> json, {
    required Iterable<String> bookUrls,
    required bool overwrite,
  }) async {
    if (overwrite) {
      _groups.clear();
      _assignments.clear();
      if (_filter != null &&
          _filter!.isNotEmpty &&
          !_groups.any((group) => group.id == _filter)) {
        _filter = null;
      }
    }
    final ids = _groups.map((group) => group.id).toSet();
    var added = 0;
    final entries = json['groups'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) continue;
        final id = entry['id'];
        final name = entry['name'];
        if (id is! String ||
            id == 'all' ||
            id.trim().isEmpty ||
            ids.contains(id) ||
            name is! String ||
            nameError(name) != null) {
          continue;
        }
        ids.add(id);
        _groups.add(ShelfGroup(id: id, name: name.trim()));
        added++;
      }
    }
    final urls = bookUrls.toSet();
    final assignments = json['assignments'];
    if (assignments is Map<String, dynamic>) {
      for (final url in urls) {
        final values = assignments[url];
        if (values is! List) continue;
        final valid = values.whereType<String>().where(ids.contains).toSet();
        if (valid.isEmpty) continue;
        final current = _assignments.putIfAbsent(url, () => <String>{});
        final before = current.length;
        current.addAll(valid);
        if (current.length > before) added++;
      }
    }
    if (!overwrite) {
      _assignments.removeWhere((url, _) => !urls.contains(url));
    }
    await _persist();
    return added;
  }

  Future<void> _persist() {
    final saved = jsonEncode({...toBackupJson(), 'filter': _filter});
    final write = (_write ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringSafe(prefsKey, saved);
    });
    _write = write;
    notifyListeners();
    return write;
  }
}
