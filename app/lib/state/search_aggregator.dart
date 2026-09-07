import 'dart:async';

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

/// 单源失败原因：超时与其它错误分开提示。
enum SearchSourceFailKind { timeout, error }

class SearchSourceFailure {
  const SearchSourceFailure({required this.name, required this.kind});

  final String name;
  final SearchSourceFailKind kind;
}

/// 搜索页状态行：对齐 six-screens ③「正在聚合 N 个源 · 2 成功 1 超时」。
String searchAggregateStatus({
  required int sourceCount,
  required int successCount,
  required int timeoutCount,
  required int errorCount,
  required bool searching,
}) {
  final counts = <String>[
    if (successCount > 0) '$successCount 成功',
    if (timeoutCount > 0) '$timeoutCount 超时',
    if (errorCount > 0) '$errorCount 失败',
  ];
  final prefix = searching ? '正在聚合' : '已聚合';
  if (counts.isEmpty) return '$prefix $sourceCount 个源';
  return '$prefix $sourceCount 个源 · ${counts.join(' ')}';
}

/// 失败源可读提示：点名源，并区分超时 / 失败。
String? searchFailureTip(Iterable<SearchSourceFailure> failures) {
  final timeouts = <String>[];
  final errors = <String>[];
  for (final f in failures) {
    switch (f.kind) {
      case SearchSourceFailKind.timeout:
        timeouts.add(f.name);
      case SearchSourceFailKind.error:
        errors.add(f.name);
    }
  }
  final parts = <String>[
    if (timeouts.isNotEmpty) '${timeouts.length} 个源超时：${timeouts.join('、')}',
    if (errors.isNotEmpty) '${errors.length} 个源失败：${errors.join('、')}',
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// 将异常归类为超时或其它失败（TimeoutException / 文案含 timeout、超时）。
SearchSourceFailKind classifySearchFailure(Object error) {
  if (error is TimeoutException) return SearchSourceFailKind.timeout;
  final text = error.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('超时')) {
    return SearchSourceFailKind.timeout;
  }
  return SearchSourceFailKind.error;
}
