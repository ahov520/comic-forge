import 'models/comic_source.dart';
import 'models/content.dart';

/// 单源操作隔离：失败只记健康，不向外冒泡（聚合搜索用）。
class SourceGuard {
  /// 成功则 [SourceHealth.markSuccess] 并返回值；失败则 [SourceHealth.markFailure] 并返回 null。
  static Future<T?> run<T>(ComicSource source, Future<T> Function() action) async {
    try {
      final value = await action();
      source.health.markSuccess();
      return value;
    } catch (e) {
      source.health.markFailure(e);
      return null;
    }
  }

  /// 成功/失败都记健康；失败仍抛出（给 FutureBuilder / 单源页用）。
  static Future<T> track<T>(ComicSource source, Future<T> Function() action) async {
    try {
      final value = await action();
      source.health.markSuccess();
      return value;
    } catch (e) {
      source.health.markFailure(e);
      rethrow;
    }
  }
}

class IsolatedSearchResult {
  IsolatedSearchResult({required this.items, required this.failedNames});
  final List<Book> items;
  final List<String> failedNames;
}

/// 聚合搜索：单源失败不拖垮整次查询，并回写健康状态。
class IsolatedSearch {
  static Future<IsolatedSearchResult> run({
    required Iterable<ComicSource> sources,
    required Future<Paged<Book>> Function(ComicSource source) search,
  }) async {
    final targets = sources
        .where((s) => s.enabled && s.rules.searchUrl.isNotEmpty)
        .toList();
    final items = <Book>[];
    final failedNames = <String>[];
    await Future.wait(targets.map((s) async {
      final page = await SourceGuard.run(s, () => search(s));
      if (page != null) {
        items.addAll(page.items);
      } else {
        failedNames.add(s.name.isNotEmpty ? s.name : s.id);
      }
    }));
    return IsolatedSearchResult(items: items, failedNames: failedNames);
  }
}
