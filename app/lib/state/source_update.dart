import 'dart:convert';

import 'package:engine/engine.dart';

/// merge 的返回：合并后的完整源列表与统计。
class SourceUpdateResult {
  SourceUpdateResult({
    required this.sources,
    required this.added,
    required this.updated,
  });

  final List<ComicSource> sources;
  final int added;
  final int updated;
}

/// 订阅仓库源更新：纯合并逻辑（可单测，不涉网络）。
class SourceUpdate {
  SourceUpdate._();

  /// 把 [incoming]（仓库最新源）合并进 [existing]（本地源库）。
  /// - 新 id → 追加（added）
  /// - 已有 id 且规则指纹变化 → 就地替换，保留启用/权重/健康记录（updated）
  /// - 指纹未变 → 原样保留（unchanged）
  /// 返回合并后的列表与统计。不修改入参。
  static SourceUpdateResult merge(
      List<ComicSource> existing, List<ComicSource> incoming) {
    final byId = <String, ComicSource>{for (final s in existing) s.id: s};
    final result = List<ComicSource>.of(existing);
    var added = 0, updated = 0;

    for (final s in incoming) {
      final old = byId[s.id];
      if (old == null) {
        byId[s.id] = s;
        result.add(s);
        added++;
        continue;
      }
      if (fingerprint(old) != fingerprint(s)) {
        s.enabled = old.enabled;
        s.weight = old.weight;
        s.lastError = old.lastError;
        s.lastFailedAt = old.lastFailedAt;
        s.failCount = old.failCount;
        s.lastOkAt = old.lastOkAt;
        final idx = result.indexWhere((e) => e.id == s.id);
        result[idx] = s;
        byId[s.id] = s;
        updated++;
      }
    }
    return SourceUpdateResult(sources: result, added: added, updated: updated);
  }

  /// 规则指纹：搜索/发现/详情/取图规则 + 请求头的变化都算更新。
  static String fingerprint(ComicSource s) =>
      jsonEncode(s.rules.toJson()) + jsonEncode(s.headers);
}

/// 一个订阅仓库的更新状态（对齐皮皮喵 gitRuleMap 的 auto 语义）。
class RepoUpdateState {
  RepoUpdateState({
    this.lastRuleVersion = -1,
    this.pendingVersion = -1,
    this.checkedAt = 0,
    this.auto = false,
  });

  /// 上次已应用的 meta.ruleVersion（-1 = 未知/仓库无版本号）。
  final int lastRuleVersion;

  /// 检查发现的新版本号（> lastRuleVersion 时待应用；-1 = 无待更新）。
  final int pendingVersion;

  /// 最近一次检查时间（epoch ms；0 = 从未检查）。
  final int checkedAt;

  /// 仓库 meta 标记的 auto（ruleAuto），自动应用新版本。
  final bool auto;

  bool get hasPending => pendingVersion > lastRuleVersion;

  Map<String, dynamic> toJson() => {
        'lastRuleVersion': lastRuleVersion,
        'pendingVersion': pendingVersion,
        'checkedAt': checkedAt,
        'auto': auto,
      };

  static RepoUpdateState fromJson(Map<String, dynamic> j) => RepoUpdateState(
        lastRuleVersion: j['lastRuleVersion'] is int ? j['lastRuleVersion'] as int : -1,
        pendingVersion: j['pendingVersion'] is int ? j['pendingVersion'] as int : -1,
        checkedAt: j['checkedAt'] is int ? j['checkedAt'] as int : 0,
        auto: j['auto'] == true,
      );
}

/// 一次仓库刷新的结果。
class RepoRefreshResult {
  RepoRefreshResult({
    required this.repo,
    required this.added,
    required this.updated,
    required this.total,
    this.track,
    this.error,
  });

  final String repo;
  final int added;
  final int updated;
  final int total;
  final String? track;

  /// 刷新失败时的错误摘要（成功为 null）。
  final String? error;

  bool get ok => error == null;

  String get summary => ok
      ? '$repo：新增 $added · 更新 $updated（共 $total 源，Track $track）'
      : '$repo：$error';
}
