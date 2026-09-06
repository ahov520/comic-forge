import 'package:engine/engine.dart';

/// 源运行时缓存与全局抓取器。
class SourceService {
  SourceService._();
  static final instance = SourceService._();

  final Fetcher fetcher = HttpFetcher(defaultHeaders: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  });

  final Map<String, SourceRuntime> _runtimes = {};

  SourceRuntime runtimeFor(ComicSource source) {
    final existing = _runtimes[source.id];
    if (existing != null && identical(existing.source, source)) return existing;
    final rt = SourceRuntime(source: source, fetcher: fetcher);
    _runtimes[source.id] = rt;
    return rt;
  }

  void evict(String id) => _runtimes.remove(id);
}
