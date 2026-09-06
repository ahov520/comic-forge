import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:flutter_js/flutter_js.dart';

/// flutter_js 实现的 JS 取图钩子：预置 env 变量后执行代码，
/// 结果取最终表达式的字符串值（图片 URL 列表）。
///
/// ppcat JS 假定 WebView 环境：注入浏览器 shim（document/console/window），
/// env 由引擎传入（html/result=页面文本、baseUrl 等）。
class FlutterJsHook {
  FlutterJsHook._();

  static final FlutterJsHook instance = FlutterJsHook._();

  /// 最小浏览器 shim：规则常用 `!!document.getElementsByTagName('html')`
  /// 探测环境，恒真即可；console 缺省兜底；window 同理。
  /// java.* 助手（对齐 ppcat 常用签名；网络类助手降级返回空串）。
  static const _prelude =
      'var document = { getElementsByTagName: function () { return [{}]; }, '
      'createElement: function () { return {}; } };\n'
      'var console = typeof console !== "undefined" ? console : '
      '{ info: function(){}, log: function(){}, error: function(){} };\n'
      'var window = typeof window !== "undefined" ? window : {};\n'
      'var java = {\n'
      '  atob: function (s) {\n'
      '    var t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";\n'
      '    s = String(s).replace(/[^A-Za-z0-9\\+\\/\\=]/g, "");\n'
      '    var out = "";\n'
      '    for (var i = 0; i < s.length;) {\n'
      '      var a = t.indexOf(s.charAt(i++)), b = t.indexOf(s.charAt(i++));\n'
      '      var c = t.indexOf(s.charAt(i++)), d = t.indexOf(s.charAt(i++));\n'
      '      var n = (a << 18) | (b << 12) | ((c | 64) << 6) | (d | 64);\n'
      '      out += String.fromCharCode((n >> 16) & 255);\n'
      '      if (c !== 64) out += String.fromCharCode((n >> 8) & 255);\n'
      '      if (d !== 64) out += String.fromCharCode(n & 255);\n'
      '    }\n'
      '    try { return decodeURIComponent(escape(out)); } catch (e) { return out; }\n'
      '  },\n'
      '  getdirecturl: function (base, u) {\n'
      '    u = String(u == null ? "" : u);\n'
      '    if (/^https?:\\/\\//.test(u)) return u;\n'
      '    base = String(base);\n'
      '    if (base.charAt(base.length - 1) !== "/") base += "/";\n'
      '    return base + u.replace(/^\\//, "");\n'
      '  },\n'
      '  getString: function () { return ""; },\n'
      '  ajax: function () { return ""; },\n'
      '  get: function () { return ""; },\n'
      '  curl: function () { return ""; },\n'
      '  getHostObj: function () { return {}; },\n'
      '  fns: {}\n'
      '};\n';

  JavascriptRuntime? _rt;
  bool _unavailable = false;

  /// 平台不支持（如 Linux 桌面）时返回 null，阅读回退普通规则解析。
  JavascriptRuntime? get _runtime {
    if (_unavailable) return null;
    try {
      return _rt ??= getJavascriptRuntime();
    } catch (_) {
      _unavailable = true;
      return null;
    }
  }

  Future<String?> call(String code, Map<String, dynamic> env) async {
    final rt = _runtime;
    if (rt == null) return null;
    final setup =
        env.entries.map((e) => 'var ${e.key} = ${jsonEncode(e.value)};').join('\n');
    try {
      final res = await rt.evaluateAsync('$_prelude$setup\n\n$code');
      final out = res.stringResult;
      if (out.isEmpty || out == 'undefined' || out == 'null') return null;
      return out;
    } catch (_) {
      return null;
    }
  }
}

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

  SourceRuntime runtimeFor(ComicSource source) {
    return _runtimes.putIfAbsent(
        source.id,
        () => SourceRuntime(
            source: source, fetcher: fetcher, jsHook: FlutterJsHook.instance.call));
  }

  Future<List<String>> imagesFor(SourceRuntime runtime, String chapterUrl) {
    return _imgFutures.putIfAbsent(chapterUrl, () => runtime.images(chapterUrl));
  }

  /// 主动预取（失败静默，不阻塞阅读）。
  void prefetchImages(SourceRuntime runtime, String chapterUrl) {
    if (_imgFutures.containsKey(chapterUrl)) return;
    imagesFor(runtime, chapterUrl).catchError((_) => const <String>[]);
  }
}
