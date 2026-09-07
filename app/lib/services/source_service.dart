import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

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

  /// 按源运行时与章节缓存原始图片：规则更新后不再复用旧定义的结果。
  /// 并发/预取仍共享请求，读取时再应用当前广告规则。
  final Map<(SourceRuntime, String), Future<List<String>>> _imgFutures = {};

  /// 订阅/更新检查用（fetcher 复用全局实例）。
  RepoClient get repoClient => RepoClient(fetcher: fetcher);

  /// 广告拦截规则（AppState 载入/设置时同步；null = 不过滤）。
  AdBlockRules? adBlock;

  /// 换源预扫缓存（key = `源id|书名`，存 Future 使并发调用共享同一飞行）：
  /// 详情页后台扫描一次，角标与换源面板复用，避免重复网络请求。会话级。
  final Map<String, Future<List<(ComicSource, Book)>>> _switchCache = {};

  /// 扫描其它启用源中的同名书（限 [maxSources]、并发 6、单源 8s 超时）。
  /// 命中优先精确同名；缓存/在途直接复用（不重复发请求）。
  Future<List<(ComicSource, Book)>> scanSwitchTargets({
    required Book book,
    required List<ComicSource> allSources,
    int maxSources = 12,
    bool useCache = true,
  }) {
    final key = '${book.sourceId}|${book.name.trim()}';
    if (useCache && _switchCache.containsKey(key)) {
      return _switchCache[key]!;
    }
    final fut = _scanSwitch(book, allSources, maxSources);
    _switchCache[key] = fut;
    return fut;
  }

  Future<List<(ComicSource, Book)>> _scanSwitch(
    Book book,
    List<ComicSource> allSources,
    int maxSources,
  ) async {
    final others = allSources
        .where((s) =>
            s.enabled &&
            s.id != book.sourceId &&
            s.rules.searchUrl.isNotEmpty)
        .take(maxSources)
        .toList();
    final results = <(ComicSource, Book)>[];
    Future<void> probe(ComicSource s) async {
      try {
        final page =
            await runtimeFor(s).search(book.name).timeout(const Duration(seconds: 8));
        Book hit = page.items.isNotEmpty ? page.items.first : Book();
        for (final b in page.items) {
          if (b.name.trim() == book.name.trim()) {
            hit = b;
            break;
          }
        }
        if (hit.name.isNotEmpty) results.add((s, hit));
      } catch (_) {
        // 单源失败跳过
      }
    }

    for (var i = 0; i < others.length; i += 6) {
      await Future.wait(others.skip(i).take(6).map(probe));
    }
    return results;
  }

  /// 测试接缝：覆盖运行时构造（null = 默认实现）。
  SourceRuntime Function(ComicSource source)? debugRuntimeOverride;

  /// 测试接缝：清空换源预扫、章节图片与运行时缓存。
  void debugClearSwitchCache() {
    _switchCache.clear();
    _imgFutures.clear();
    _runtimes.clear();
  }

  SourceRuntime runtimeFor(ComicSource source) {
    final cached = _runtimes[source.id];
    if (cached != null && identical(cached.source, source)) return cached;
    if (cached != null) {
      _imgFutures.removeWhere((key, _) => identical(key.$1, cached));
    }
    final override = debugRuntimeOverride;
    return _runtimes[source.id] = override != null
        ? override(source)
        : SourceRuntime(
            source: source, fetcher: fetcher, jsHook: FlutterJsHook.instance.call);
  }

  Future<List<String>> imagesFor(
    SourceRuntime runtime,
    String chapterUrl, {
    bool refresh = false,
  }) async {
    final key = (runtime, chapterUrl);
    var future = refresh ? null : _imgFutures[key];
    if (future == null) {
      final request = Future<List<String>>.sync(() => runtime.images(chapterUrl));
      _imgFutures[key] = request;
      unawaited(request.then<void>((_) {}, onError: (Object _, StackTrace _) {
        // 失败不缓存；旧请求晚到不能删除重试后的新结果。
        if (identical(_imgFutures[key], request)) {
          _imgFutures.remove(key);
        }
      }));
      future = request;
    }
    final urls = await future;
    return adBlock?.filterImages(urls) ?? urls;
  }

  /// 主动预取（失败静默，不阻塞阅读）。
  void prefetchImages(SourceRuntime runtime, String chapterUrl) {
    if (_imgFutures.containsKey((runtime, chapterUrl))) return;
    imagesFor(runtime, chapterUrl).catchError((_) => const <String>[]);
  }

  /// 预热下一话前 N 张图片到图片缓存（翻页接近末页时调用）。
  /// 静默失败；URL 列表先经 imagesFor（命中已有的预取）。
  void precacheLeadingImages(
    BuildContext context,
    SourceRuntime runtime,
    String chapterUrl, {
    int count = 3,
  }) {
    final urls = imagesFor(runtime, chapterUrl);
    unawaited(urls.then((list) async {
      for (final u in list.take(count)) {
        if (!context.mounted) return;
        try {
          await precacheImage(
            CachedNetworkImageProvider(
                u, headers: runtime.imageRequestHeaders.isEmpty
                    ? runtime.source.headers
                    : {
                        ...runtime.source.headers,
                        ...runtime.imageRequestHeaders,
                      }),
            context,
          );
        } catch (_) {
          return; // 第一张失败即放弃本轮预热
        }
      }
    }).catchError((_) {}));
  }
}
