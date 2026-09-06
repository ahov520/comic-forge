import 'models/comic_source.dart';
import 'models/source_health.dart';

/// 源库合并模式。
enum SourceMergeMode {
  /// 恢复内置：只追加新源；已有源仅在缺 searchUrl/headers 时补规则，保留启用与权重。
  restoreBuiltins,

  /// 订阅/商店导入：按 id 去重后 upsert 规则，保留用户启用与权重，不产生重复条目。
  subscribe,
}

class SourceMergeResult {
  SourceMergeResult({
    this.added = 0,
    this.updated = 0,
    this.repaired = 0,
    this.skippedDupes = 0,
    this.skippedInvalid = 0,
  });

  final int added;
  final int updated;
  final int repaired;
  final int skippedDupes;
  final int skippedInvalid;

  int get changed => added + updated + repaired;
}

/// 源目录：稳定的按 id 去重与合并（内置恢复 / 订阅导入共用）。
class SourceCatalog {
  /// 用于去重的稳定 id：优先 [ComicSource.id]，否则 url，再否则 name。
  static String idOf(ComicSource s) {
    if (s.id.isNotEmpty) return s.id;
    if (s.url.isNotEmpty) return s.url;
    return s.name;
  }

  /// 丢弃无 id/url/name 的坏条目；同一 id 保留最后一条。
  static List<ComicSource> dedupe(Iterable<ComicSource> incoming) {
    final map = <String, ComicSource>{};
    for (final s in incoming) {
      final id = idOf(s);
      if (id.isEmpty) continue;
      if (s.id.isEmpty) s.id = id;
      map[id] = s;
    }
    return map.values.toList();
  }

  /// 把 [incoming] 合并进 [existing]（原地修改 [existing]）。
  ///
  /// 两种模式都保留已有源的 [ComicSource.enabled] / [ComicSource.weight]。
  /// 恢复模式不覆盖已完好的规则；订阅模式更新规则但保留健康记录。
  static SourceMergeResult merge(
    List<ComicSource> existing,
    Iterable<ComicSource> incoming, {
    required SourceMergeMode mode,
  }) {
    final incomingList = incoming.toList();
    final unique = dedupe(incomingList);
    final skippedInvalid = incomingList.where((s) => idOf(s).isEmpty).length;
    final skippedDupes = incomingList.length - unique.length - skippedInvalid;

    var added = 0;
    var updated = 0;
    var repaired = 0;

    for (final s in unique) {
      final id = idOf(s);
      final idx = existing.indexWhere((e) => idOf(e) == id);
      if (idx < 0) {
        existing.add(s);
        added++;
        continue;
      }
      final old = existing[idx];
      s.enabled = old.enabled;
      s.weight = old.weight;

      if (mode == SourceMergeMode.restoreBuiltins) {
        final needsSearchUrl =
            old.rules.searchUrl.isEmpty && s.rules.searchUrl.isNotEmpty;
        final needsHeaders = old.headers.isEmpty && s.headers.isNotEmpty;
        if (needsSearchUrl || needsHeaders) {
          s.health = SourceHealth();
          existing[idx] = s;
          repaired++;
        }
      } else {
        s.health = old.health;
        existing[idx] = s;
        updated++;
      }
    }

    return SourceMergeResult(
      added: added,
      updated: updated,
      repaired: repaired,
      skippedDupes: skippedDupes,
      skippedInvalid: skippedInvalid,
    );
  }
}
