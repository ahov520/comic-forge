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
  /// 按 id 去重：新源追加；已有源若缺 searchUrl/headers 则补回规则（保留启用与权重）。
  /// 返回新增 + 修复数量。
  Future<int> importBuiltinSources() async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['sources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat);
    // 只增不删会让旧版映射丢掉的 searchUrl 永久空着；恢复时补回规则/请求头，保留启用与权重。
    final result = SourceCatalog.merge(
      sources,
      list,
      mode: SourceMergeMode.restoreBuiltins,
    );
    if (result.changed > 0) {
      await persistSources();
    }
    return result.changed;
  }

  Future<void> _persistSources() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSources, jsonEncode(sources.map((s) => s.toJson()).toList()));
  }

  /// 写回源列表并通知 UI（健康状态变更后调用）。
  Future<void> persistSources() async {
    await _persistSources();
    notifyListeners();
  }

  Future<void> addRepoSubscribed(String repoUrl, List<ComicSource> imported) async {
    if (!repos.contains(repoUrl)) repos.add(repoUrl);
    SourceCatalog.merge(sources, imported, mode: SourceMergeMode.subscribe);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kRepos, jsonEncode(repos));
    await persistSources();
  }

  Future<void> addSourceManual(ComicSource s) async {
    SourceCatalog.merge(sources, [s], mode: SourceMergeMode.subscribe);
    await persistSources();
  }

  Future<void> removeSource(String id) async {
    sources.removeWhere((e) => e.id == id);
    await persistSources();
  }

  Future<void> toggleSource(String id) async {
    for (final s in sources) {
      if (s.id == id) s.enabled = !s.enabled;
    }
    await persistSources();
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    for (final s in sources) {
      if (s.id == id) s.enabled = enabled;
    }
    await persistSources();
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
