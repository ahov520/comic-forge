import 'package:engine/engine.dart';

/// 聚合搜索结果加工：去重（同名同作者）+ 按源权重排序 + 命中统计。
class SearchAggregator {
  SearchAggregator._();

  /// [raw] 每源结果（key = 源 id，顺序 = 到达顺序）；
  /// [weightOf] 源 id → 权重（大者优先）。
  static AggregatedSearch aggregate(
    Map<String, List<Book>> raw,
    int Function(String sourceId) weightOf,
  ) {
    // 源权重表（一次构建）
    final weights = {for (final id in raw.keys) id: weightOf(id)};

    // 到达顺序：按首个命中结果的先后（Map 插入序）
    final arrival = <String, int>{};
    var order = 0;
    for (final entry in raw.entries) {
      if (entry.value.isEmpty) continue;
      arrival[entry.key] = order++;
    }

    // 平铺并标注来源
    final tagged = <(Book, String)>[];
    for (final entry in raw.entries) {
      for (final b in entry.value) {
        tagged.add((b, entry.key));
      }
    }

    // 去重：normalize(名+作者) 相同视为同一部，保留权重高者；
    // 权重相同保留先到达者。记录被合并的条数。
    final best = <String, (Book, String)>{};
    var duplicates = 0;
    for (final t in tagged) {
      final key = _dedupKey(t.$1);
      final cur = best[key];
      if (cur == null) {
        best[key] = t;
        continue;
      }
      final curW = weights[cur.$2] ?? 0;
      final newW = weights[t.$2] ?? 0;
      if (newW > curW ||
          (newW == curW &&
              (arrival[t.$2] ?? 1 << 30) < (arrival[cur.$2] ?? 1 << 30))) {
        best[key] = t;
      }
      duplicates++;
    }

    // 排序：源权重降序 → 源到达序 → 原始顺序（稳定）
    final books = best.values.toList()
      ..sort((a, b) {
        final w = (weights[b.$2] ?? 0).compareTo(weights[a.$2] ?? 0);
        if (w != 0) return w;
        final r = (arrival[a.$2] ?? 0).compareTo(arrival[b.$2] ?? 0);
        return r;
      });

    return AggregatedSearch(
      books: books.map((t) => t.$1).toList(),
      sourceIds: books.map((t) => t.$2).toList(),
      sourcesHit: arrival.length,
      duplicatesRemoved: duplicates,
    );
  }

  /// 去重键：名称+作者（去空白、忽略大小写）。
  static String _dedupKey(Book b) =>
      '${b.name.trim().toLowerCase()}|${b.author.trim().toLowerCase()}';
}

/// 聚合结果：条目（与 sourceIds 一一对应，供 UI 显示来源标签）。
class AggregatedSearch {
  AggregatedSearch({
    required this.books,
    required this.sourceIds,
    required this.sourcesHit,
    required this.duplicatesRemoved,
  });

  final List<Book> books;
  final List<String> sourceIds;
  final int sourcesHit;
  final int duplicatesRemoved;
}
