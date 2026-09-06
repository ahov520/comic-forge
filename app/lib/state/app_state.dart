import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';

/// 全局应用状态：源库、书架、订阅仓库。
class AppState extends ChangeNotifier {
  static const _kSources = 'cf.sources';
  static const _kRepos = 'cf.repos';
  static const _kShelf = 'cf.shelf';
  static const _kDark = 'cf.dark';

  final List<ComicSource> sources = [];
  final List<String> repos = [];
  final List<Book> shelf = [];
  bool darkMode = true;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    sources
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kSources) ?? '[]') as List)
          .whereType<Map<String, dynamic>>()
          .map(ComicSource.fromJson));
    repos
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kRepos) ?? '[]') as List).cast<String>());
    shelf
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kShelf) ?? '[]') as List)
          .whereType<Map<String, dynamic>>()
          .map(Book.fromJson));
    darkMode = sp.getBool(_kDark) ?? true;
    // 首次启动自动导入内置源快照
    if (sources.isEmpty) {
      await importBuiltinSources();
    }
  }

  /// 导入 APK 内置的源快照（assets/store.json，493 条社区规则文本）。
  /// 按 id 去重，只增不删；返回新增数量。
  Future<int> importBuiltinSources() async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['sources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat);
    var added = 0;
    final known = sources.map((s) => s.id).toSet();
    for (final s in list) {
      if (known.contains(s.id)) continue;
      known.add(s.id);
      sources.add(s);
      added++;
    }
    if (added > 0) {
      await _persistSources();
      notifyListeners();
    }
    return added;
  }

  Future<void> _persistSources() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSources, jsonEncode(sources.map((s) => s.toJson()).toList()));
  }

  Future<void> addRepoSubscribed(String repoUrl, List<ComicSource> imported) async {
    if (!repos.contains(repoUrl)) repos.add(repoUrl);
    for (final s in imported) {
      sources.removeWhere((e) => e.id == s.id);
      sources.add(s);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kRepos, jsonEncode(repos));
    await _persistSources();
    notifyListeners();
  }

  Future<void> addSourceManual(ComicSource s) async {
    sources.removeWhere((e) => e.id == s.id);
    sources.add(s);
    await _persistSources();
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    sources.removeWhere((e) => e.id == id);
    await _persistSources();
    notifyListeners();
  }

  Future<void> toggleSource(String id) async {
    for (final s in sources) {
      if (s.id == id) s.enabled = !s.enabled;
    }
    await _persistSources();
    notifyListeners();
  }

  Future<void> toggleShelf(Book b) async {
    final exists = shelf.any((e) => e.bookUrl == b.bookUrl);
    if (exists) {
      shelf.removeWhere((e) => e.bookUrl == b.bookUrl);
    } else {
      shelf.insert(0, b);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kShelf, jsonEncode(shelf.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  bool inShelf(Book b) => shelf.any((e) => e.bookUrl == b.bookUrl);

  Future<void> setDark(bool v) async {
    darkMode = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDark, v);
    notifyListeners();
  }
}
