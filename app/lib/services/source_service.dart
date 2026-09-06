import 'package:engine/engine.dart';

import 'js_hook.dart';

/// 源运行时缓存与全局抓取器。
class SourceService {
  SourceService._();
  static final instance = SourceService._();

  final Fetcher fetcher = HttpFetcher(defaultHeaders: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  });

  final Map<String, SourceRuntime> _runtimes = {};

  /// 章节图片 Future 缓存：同章节去重 + 预加载下一话复用。
  final Map<String, Future<List<String>>> _imgFutures = {};

  /// 订阅/更新检查用（fetcher 复用全局实例）。
  RepoClient get repoClient => RepoClient(fetcher: fetcher);

  /// 广告拦截规则（AppState 载入/设置时同步；null = 不过滤）。
  AdBlockRules? adBlock;

  SourceRuntime runtimeFor(ComicSource source) {
    return _runtimes.putIfAbsent(
        source.id,
        () => SourceRuntime(
            source: source, fetcher: fetcher, jsHook: FlutterJsHook.instance.call));
  }

  Future<List<String>> imagesFor(SourceRuntime runtime, String chapterUrl) {
    return _imgFutures.putIfAbsent(chapterUrl, () async {
      final urls = await runtime.images(chapterUrl);
      return adBlock?.filterImages(urls) ?? urls;
    });
  }

  /// 主动预取（失败静默，不阻塞阅读）。
  void prefetchImages(SourceRuntime runtime, String chapterUrl) {
    if (_imgFutures.containsKey(chapterUrl)) return;
    imagesFor(runtime, chapterUrl).catchError((_) => const <String>[]);
  }
}
