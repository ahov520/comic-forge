import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';

/// null 表示全部源，空集合表示用户明确未选择任何源。
class SearchFilters {
  SearchFilters({this.onlyHealthy = false, Set<String>? sourceIds})
    : sourceIds = sourceIds == null ? null : Set.unmodifiable(sourceIds);

  final bool onlyHealthy;
  final Set<String>? sourceIds;
  bool get isActive => onlyHealthy || sourceIds != null;

  bool accepts(ComicSource source, {bool ignoreHealth = false}) =>
      source.enabled &&
      source.rules.searchUrl.isNotEmpty &&
      (sourceIds == null || sourceIds!.contains(source.id)) &&
      (ignoreHealth || !onlyHealthy || !source.isUnhealthy);

  Map<String, dynamic> toJson() => {
    'onlyHealthy': onlyHealthy,
    'sourceIds': sourceIds?.toList(),
  };

  factory SearchFilters.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return SearchFilters();
    final ids = json['sourceIds'];
    return SearchFilters(
      onlyHealthy: json['onlyHealthy'] == true,
      sourceIds: ids is List
          ? ids.whereType<String>().where((id) => id.isNotEmpty).toSet()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      onlyHealthy == other.onlyHealthy &&
      setEquals(sourceIds, other.sourceIds);

  @override
  int get hashCode => Object.hash(
    onlyHealthy,
    sourceIds == null ? null : Object.hashAllUnordered(sourceIds!),
  );
}
