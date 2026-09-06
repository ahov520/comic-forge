import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';

import 'source_update.dart';
import '../services/source_service.dart';

/// 阅读进度（按书记忆，重启可续读）。
class ReadingProgress {
  ReadingProgress({
    required this.bookUrl,
    required this.sourceId,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.at,
  });

  final String bookUrl;
  final String sourceId;
  final String chapterUrl;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final int at;

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'sourceId': sourceId,
        'chapterUrl': chapterUrl,
        'chapterTitle': chapterTitle,
        'chapterIndex': chapterIndex,
        'chapterCount': chapterCount,
        'at': at,
      };

  static ReadingProgress fromJson(Map<String, dynamic> j) => ReadingProgress(
        bookUrl: j['bookUrl'] as String? ?? '',
        sourceId: j['sourceId'] as String? ?? '',
        chapterUrl: j['chapterUrl'] as String? ?? '',
        chapterTitle: j['chapterTitle'] as String? ?? '',
        chapterIndex: j['chapterIndex'] as int? ?? 0,
        chapterCount: j['chapterCount'] as int? ?? 0,
        at: j['at'] as int? ?? 0,
      );
}

/// 书籍详情离线缓存（章节目录 stale-while-revalidate）。
class CachedDetail {
  CachedDetail({required this.book, required this.chapters, required this.at});

  final Book book;
  final List<Chapter> chapters;
  final int at;

  Map<String, dynamic> toJson() => {
        'book': book.toJson(),
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'at': at,
      };

  static CachedDetail fromJson(Map<String, dynamic> j) => CachedDetail(
        book: Book.fromJson(j['book'] as Map<String, dynamic>),
        chapters: (j['chapters'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Chapter.fromJson)
            .toList(),
        at: j['at'] as int? ?? 0,
      );
}

/// 全局应用状态：源库、书架、订阅仓库。
class AppState extends ChangeNotifier {
  static const _kSources = 'cf.sources';
  static const _kRepos = 'cf.repos';
  static const _kShelf = 'cf.shelf';
  static const _kDark = 'cf.dark';
  static const _kProgress = 'cf.progress';
  static const _kDetailCache = 'cf.detailCache';
  static const _kReaderBrightness = 'cf.readerBrightness';
  static const _kRepoRefresh = 'cf.repoRefresh';
  static const _kRepoUpdates = 'cf.repoUpdates';
  static const _kAdBlock = 'cf.adBlock';
  static const _kWebDav = 'cf.webdav';
  static const _detailCacheCap = 100;

  /// 启动自动检查间隔：6 小时内不重复检查。
  static const _autoCheckIntervalMs = 6 * 3600 * 1000;

  final List<ComicSource> sources = [];
  final List<String> repos = [];
  final List<Book> shelf = [];
  final Map<String, ReadingProgress> progress = {}; // key: bookUrl
  final Map<String, CachedDetail> detailCache = {}; // key: bookUrl
  final Map<String, int> repoLastRefresh = {}; // key: repo url, epoch ms
  final Map<String, RepoUpdateState> repoUpdates = {}; // key: repo url
  /// 广告拦截规则（null = 未启用）。
  AdBlockRules? adBlock;
  /// WebDAV 配置（url/user/pass/path；明文存本地，仅本机使用）。
  Map<String, String>? webDavConfig;
  bool darkMode = true;
  /// 阅读器遮罩亮度（0.15~1.0，1 = 不加暗）。
  double readerBrightness = 1.0;

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
    progress
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kProgress) ?? '{}') as Map<String, dynamic>)
          .map((k, v) => MapEntry(
              k, ReadingProgress.fromJson(v as Map<String, dynamic>))));
    detailCache
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kDetailCache) ?? '{}') as Map<String, dynamic>)
          .map((k, v) =>
              MapEntry(k, CachedDetail.fromJson(v as Map<String, dynamic>))));
    repoLastRefresh
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kRepoRefresh) ?? '{}') as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)));
    repoUpdates
      ..clear()
      ..addAll((jsonDecode(sp.getString(_kRepoUpdates) ?? '{}') as Map<String, dynamic>)
          .map((k, v) =>
              MapEntry(k, RepoUpdateState.fromJson(v as Map<String, dynamic>))));
    final adText = sp.getString(_kAdBlock);
    adBlock = adText == null ? null : AdBlockRules.tryParse(adText);
    SourceService.instance.adBlock = adBlock;
    final wd = sp.getString(_kWebDav);
    webDavConfig = wd == null
        ? null
        : (jsonDecode(wd) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v.toString()));
    darkMode = sp.getBool(_kDark) ?? true;
    readerBrightness = sp.getDouble(_kReaderBrightness) ?? 1.0;
    // 首次启动自动导入内置源快照
    if (sources.isEmpty) {
      await importBuiltinSources();
    }
  }

  /// 记录阅读进度（打开章节时调用；同一本书只保留最新）。
  Future<void> saveProgress(Book book,
      {required String chapterUrl,
      required String chapterTitle,
      required int chapterIndex,
      required int chapterCount}) async {
    progress[book.bookUrl] = ReadingProgress(
      bookUrl: book.bookUrl,
      sourceId: book.sourceId ?? '',
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kProgress,
        jsonEncode(progress
            .map((k, v) => MapEntry(k, v.toJson()))));
    notifyListeners();
  }

  ReadingProgress? progressFor(String bookUrl) => progress[bookUrl];

  /// 章节目录缓存（离线可见 + 秒开），成功拉取详情后调用；超上限按时间淘汰。
  Future<void> saveDetailCache(Book book, List<Chapter> chapters) async {
    if (book.bookUrl.isEmpty || chapters.isEmpty) return;
    detailCache[book.bookUrl] = CachedDetail(
        book: book,
        chapters: chapters,
        at: DateTime.now().millisecondsSinceEpoch);
    while (detailCache.length > _detailCacheCap) {
      String? oldest;
      int? oldestAt;
      detailCache.forEach((k, v) {
        if (oldestAt == null || v.at < oldestAt!) {
          oldest = k;
          oldestAt = v.at;
        }
      });
      if (oldest == null) break;
      detailCache.remove(oldest);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kDetailCache,
        jsonEncode(detailCache.map((k, v) => MapEntry(k, v.toJson()))));
  }

  CachedDetail? detailCacheFor(String bookUrl) => detailCache[bookUrl];

  /// 检查一个订阅仓库的更新：重新拉取 store，规则有变则就地更新（保留
  /// 启用/权重/健康），新增源直接追加。[client] 可注入（测试用）。
  Future<RepoRefreshResult> refreshRepo(String repoUrl, {RepoClient? client}) async {
    final c = client ?? SourceService.instance.repoClient;
    try {
      final bundle = await c.subscribe(repoUrl);
      final r = SourceUpdate.merge(sources, bundle.sources);
      sources
        ..clear()
        ..addAll(r.sources);
      repoLastRefresh[repoUrl] = DateTime.now().millisecondsSinceEpoch;
      _recordRepoVersion(repoUrl, bundle.meta.ruleVersion,
          metaAuto: bundle.meta.ruleAuto);
      await _persistRepoMeta();
      await _persistSources();
      notifyListeners();
      return RepoRefreshResult(
        repo: repoUrl,
        added: r.added,
        updated: r.updated,
        total: bundle.sources.length,
        track: bundle.track,
      );
    } catch (e) {
      final msg = e.toString().split('\n').first;
      return RepoRefreshResult(repo: repoUrl, added: 0, updated: 0, total: 0, error: msg);
    }
  }

  /// 逐个检查全部订阅仓库。
  Future<List<RepoRefreshResult>> refreshAllRepos({RepoClient? client}) async {
    final out = <RepoRefreshResult>[];
    for (final repo in repos) {
      out.add(await refreshRepo(repo, client: client));
    }
    return out;
  }

  void _recordRepoVersion(String repoUrl, int ruleVersion, {bool? metaAuto}) {
    final st = repoUpdates[repoUrl] ?? RepoUpdateState();
    repoUpdates[repoUrl] = RepoUpdateState(
      lastRuleVersion: ruleVersion,
      pendingVersion: -1,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
      auto: metaAuto ?? st.auto,
    );
  }

  Future<void> _persistRepoMeta() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kRepoRefresh, jsonEncode(repoLastRefresh));
    await sp.setString(
        _kRepoUpdates,
        jsonEncode(repoUpdates.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// 轻量版本检查：只拉各仓库 meta（不拉全量 store），比对 ruleVersion。
  /// 新版本 → 标记 pending（meta.ruleAuto 时立即自动应用）。
  /// 仓库无版本号（ruleVersion=0）时退化为全量刷新比对。
  Future<List<String>> checkRepoUpdates({RepoClient? client}) async {
    final c = client ?? SourceService.instance.repoClient;
    final notices = <String>[];
    for (final repoUrl in repos) {
      try {
        final meta = await c.fetchMeta(repoUrl);
        final st = repoUpdates[repoUrl] ?? RepoUpdateState();
        final checkedAt = DateTime.now().millisecondsSinceEpoch;
        if (meta.ruleVersion > 0 &&
            st.lastRuleVersion >= 0 &&
            meta.ruleVersion > st.lastRuleVersion) {
          // 有新版本
          repoUpdates[repoUrl] = RepoUpdateState(
            lastRuleVersion: st.lastRuleVersion,
            pendingVersion: meta.ruleVersion,
            checkedAt: checkedAt,
            auto: meta.ruleAuto,
          );
          if (meta.ruleAuto) {
            await refreshRepo(repoUrl, client: c);
            notices.add('$repoUrl：已自动更新到 v${meta.ruleVersion}');
          } else {
            notices.add('$repoUrl：发现新版本 v${meta.ruleVersion}');
          }
        } else if (meta.ruleVersion == 0) {
          // 仓库无版本号：退化为全量刷新做内容比对
          final r = await refreshRepo(repoUrl, client: c);
          if (r.ok && (r.added > 0 || r.updated > 0)) {
            notices.add('$repoUrl：源有变更（新增 ${r.added} · 更新 ${r.updated}）');
          }
        } else {
          repoUpdates[repoUrl] = RepoUpdateState(
            lastRuleVersion: st.lastRuleVersion,
            pendingVersion: st.pendingVersion,
            checkedAt: checkedAt,
            auto: meta.ruleAuto,
          );
        }
      } catch (e) {
        // 检查失败不打断其他仓库
        continue;
      }
    }
    if (repoUpdates.isNotEmpty || repoLastRefresh.isNotEmpty) {
      await _persistRepoMeta();
      notifyListeners();
    }
    return notices;
  }

  /// 启动自动检查（节流：距上次检查不足 [_autoCheckIntervalMs] 则跳过）。
  /// 静默执行，结果通过 repoUpdates/notifyListeners 反映。
  Future<void> autoCheckUpdates({RepoClient? client}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = repos.any((r) {
      final st = repoUpdates[r];
      return st == null || now - st.checkedAt > _autoCheckIntervalMs;
    });
    if (!due) return;
    await checkRepoUpdates(client: client);
  }

  /// 应用一个仓库的待更新版本（等价全量刷新）。
  Future<RepoRefreshResult> applyRepoUpdate(String repoUrl, {RepoClient? client}) =>
      refreshRepo(repoUrl, client: client);

  /// 合并备份载荷：源按 id 替换（备份优先）、书架并集、进度取较新、
  /// 订阅仓库并集。单次持久化 + 单次通知。
  Future<({int sources, int shelf, int progress, int repos})> mergeBackup({
    required List<ComicSource> sources,
    required List<Book> shelf,
    required Map<String, ReadingProgress> progress,
    required List<String> repos,
  }) async {
    var nSrc = 0, nShelf = 0, nProg = 0, nRepo = 0;

    for (final s in sources) {
      final idx = this.sources.indexWhere((e) => e.id == s.id);
      if (idx < 0) {
        this.sources.add(s);
        nSrc++;
      } else if (SourceUpdate.fingerprint(this.sources[idx]) !=
          SourceUpdate.fingerprint(s)) {
        // 保留本地启用/权重/健康，规则以备份为准
        s.enabled = this.sources[idx].enabled;
        s.weight = this.sources[idx].weight;
        s.failCount = this.sources[idx].failCount;
        s.lastError = this.sources[idx].lastError;
        s.lastFailedAt = this.sources[idx].lastFailedAt;
        s.lastOkAt = this.sources[idx].lastOkAt;
        this.sources[idx] = s;
        nSrc++;
      }
    }
    for (final b in shelf) {
      if (!this.shelf.any((e) => e.bookUrl == b.bookUrl)) {
        this.shelf.add(b);
        nShelf++;
      }
    }
    progress.forEach((k, v) {
      final cur = this.progress[k];
      if (cur == null || v.at > cur.at) {
        this.progress[k] = v;
        nProg++;
      }
    });
    for (final r in repos) {
      if (!this.repos.contains(r)) {
        this.repos.add(r);
        nRepo++;
      }
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSources, jsonEncode(this.sources.map((s) => s.toJson()).toList()));
    await sp.setString(_kShelf, jsonEncode(this.shelf.map((e) => e.toJson()).toList()));
    await sp.setString(_kProgress,
        jsonEncode(this.progress.map((k, v) => MapEntry(k, v.toJson()))));
    await sp.setString(_kRepos, jsonEncode(this.repos));
    notifyListeners();
    return (sources: nSrc, shelf: nShelf, progress: nProg, repos: nRepo);
  }

  /// 待更新仓库数（角标用）。
  int get pendingUpdateCount =>
      repoUpdates.values.where((s) => s.hasPending).length;

  /// 导入 APK 内置的源快照（assets/store.json，493 条社区规则文本）。
  /// 按 id 去重：新源追加；已有源若缺 searchUrl/headers 则补回规则（保留启用与权重）。
  /// 返回新增 + 修复数量。
  Future<int> importBuiltinSources() async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['sources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat);
    var added = 0;
    var repaired = 0;
    for (final s in list) {
      final idx = sources.indexWhere((e) => e.id == s.id);
      if (idx < 0) {
        sources.add(s);
        added++;
        continue;
      }
      // 只增不删会让旧版映射丢掉的 searchUrl 永久空着；恢复时补回规则/请求头，
      // 保留启用/权重/健康记录（避免抹掉已知失效信息）。
      final existing = sources[idx];
      final needsSearchUrl =
          existing.rules.searchUrl.isEmpty && s.rules.searchUrl.isNotEmpty;
      final needsHeaders = existing.headers.isEmpty && s.headers.isNotEmpty;
      if (needsSearchUrl || needsHeaders) {
        s.enabled = existing.enabled;
        s.weight = existing.weight;
        s.lastError = existing.lastError;
        s.lastFailedAt = existing.lastFailedAt;
        s.failCount = existing.failCount;
        s.lastOkAt = existing.lastOkAt;
        sources[idx] = s;
        repaired++;
      }
    }
    if (added > 0 || repaired > 0) {
      await _persistSources();
      notifyListeners();
    }
    return added + repaired;
  }

  /// 批量回报源健康：[okIds] 本轮成功的源；[errors] 失败 {源id: 错误摘要}。
  /// 成功清零连续失败计数；失败累加并记原因/时间。一次持久化 + 一次通知。
  Future<void> reportSourceHealth(
      Iterable<String> okIds, Map<String, String> errors) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final id in okIds) {
      final s = _find(id);
      if (s == null) continue;
      if (s.failCount != 0 || s.lastError.isNotEmpty || s.lastOkAt == 0) {
        changed = true;
      }
      s.failCount = 0;
      s.lastError = '';
      s.lastOkAt = now;
    }
    errors.forEach((id, err) {
      final s = _find(id);
      if (s == null) return;
      final msg = err.length > 120 ? err.substring(0, 120) : err;
      if (s.lastError != msg || s.lastFailedAt == 0) changed = true;
      s.lastError = msg;
      s.lastFailedAt = now;
      s.failCount++;
    });
    if (changed) {
      await _persistSources();
      notifyListeners();
    }
  }

  /// 一键禁用失效候选（连续失败 ≥3 的启用源）。返回禁用数量。
  Future<int> disableUnhealthySources() async {
    var n = 0;
    for (final s in sources) {
      if (s.enabled && s.isUnhealthy) {
        s.enabled = false;
        n++;
      }
    }
    if (n > 0) {
      await _persistSources();
      notifyListeners();
    }
    return n;
  }

  /// 清空全部失败记录（重新探活时用）。
  Future<int> resetSourceHealth() async {
    var n = 0;
    for (final s in sources) {
      if (s.failCount != 0 || s.lastError.isNotEmpty || s.lastFailedAt != 0) {
        s.failCount = 0;
        s.lastError = '';
        s.lastFailedAt = 0;
        n++;
      }
    }
    if (n > 0) {
      await _persistSources();
      notifyListeners();
    }
    return n;
  }

  ComicSource? _find(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
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

  /// 阅读器亮度（遮罩式调暗，持久化全局）。
  Future<void> setReaderBrightness(double v) async {
    readerBrightness = v.clamp(0.15, 1.0);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kReaderBrightness, readerBrightness);
    notifyListeners();
  }

  /// 保存 WebDAV 配置（null 清除）。
  Future<void> setWebDavConfig(Map<String, String>? cfg) async {
    webDavConfig = cfg;
    final sp = await SharedPreferences.getInstance();
    if (cfg == null) {
      await sp.remove(_kWebDav);
    } else {
      await sp.setString(_kWebDav, jsonEncode(cfg));
    }
    notifyListeners();
  }

  /// 导入广告拦截规则 JSON（坏 JSON 返回 false）；text 为 null/空则清除。
  Future<bool> setAdBlock(String? text) async {
    final sp = await SharedPreferences.getInstance();
    if (text == null || text.trim().isEmpty) {
      adBlock = null;
      SourceService.instance.adBlock = null;
      await sp.remove(_kAdBlock);
      notifyListeners();
      return true;
    }
    final rules = AdBlockRules.tryParse(text);
    if (rules == null) return false;
    adBlock = rules;
    SourceService.instance.adBlock = rules;
    await sp.setString(_kAdBlock, text);
    notifyListeners();
    return true;
  }
}
