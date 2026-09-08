import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'package:engine/engine.dart';

import 'js_hook.dart';

class _SwitchScan {
  const _SwitchScan(this.sources, this.result);

  final List<ComicSource> sources;
  final Future<List<(ComicSource, Book)>> result;
}

/// 源运行时缓存与全局抓取器。
class SourceService {
  SourceService._();
  static final instance = SourceService._();

  /// 全局域名黑名单（设置页维护；抓取与阅读器图片共用）。
  final NetworkPolicy networkPolicy = NetworkPolicy();

  late final Fetcher fetcher = HttpFetcher(
    defaultHeaders: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    },
    policy: networkPolicy,
  );

  final Map<String, SourceRuntime> _runtimes = {};

  /// 按源运行时与章节缓存原始图片：规则更新后不再复用旧定义的结果。
  /// 并发/预取仍共享请求，读取时再应用当前广告规则。
  final Map<(SourceRuntime, String), Future<List<String>>> _imgFutures = {};

  /// 订阅/更新检查用（fetcher 复用全局实例）。
  RepoClient get repoClient => RepoClient(fetcher: fetcher);

  /// 广告拦截规则（AppState 载入/设置时同步；null = 不过滤）。
  AdBlockRules? adBlock;

  /// 按当前源与书名缓存换源扫描；同一组候选源的角标与面板共享请求。
  final Map<(String?, String), _SwitchScan> _switchCache = {};

  /// 扫描其它启用源中的同名书（限 [maxSources]、并发 6、单源 8s 超时）。
  /// 命中优先精确同名；缓存/在途直接复用（不重复发请求）。
  Future<List<(ComicSource, Book)>> scanSwitchTargets({
    required Book book,
    required List<ComicSource> allSources,
    int maxSources = 12,
    bool useCache = true,
  }) {
    final others = allSources
        .where((s) =>
            s.enabled &&
            s.id != book.sourceId &&
            s.rules.searchUrl.isNotEmpty)
        .take(maxSources)
        .toList(growable: false);
    final key = (book.sourceId, book.name.trim());
    final cached = _switchCache[key];
    if (useCache && cached != null && listEquals(cached.sources, others)) {
      return cached.result;
    }
    final fut = _scanSwitch(book, others);
    final scan = _SwitchScan(others, fut);
    _switchCache[key] = scan;
    unawaited(fut.then<void>((_) {}, onError: (Object _, StackTrace _) {
      if (identical(_switchCache[key], scan)) _switchCache.remove(key);
    }));
    return fut;
  }

  Future<List<(ComicSource, Book)>> _scanSwitch(
    Book book,
    List<ComicSource> others,
  ) async {
    final results = <(ComicSource, Book)>[];
    var succeeded = 0;
    Future<void> probe(ComicSource s) async {
      try {
        final page =
            await runtimeFor(s).search(book.name).timeout(const Duration(seconds: 8));
        succeeded++;
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
    if (others.isNotEmpty && succeeded == 0) {
      throw StateError('所有候选源查找失败');
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

  /// 丢掉章节图片 URL 的内存缓存，不触及离线下载文件。
  void clearChapterImageCache({String? sourceId}) {
    if (sourceId == null) {
      _imgFutures.clear();
      return;
    }
    _imgFutures.removeWhere((key, _) => key.$1.source.id == sourceId);
  }

  /// 测试接缝：清空域名黑名单，避免用例互相污染。
  void debugResetNetworkPolicy() {
    networkPolicy.replaceAll(const []);
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
        if (networkPolicy.isBlocked(u)) continue;
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
