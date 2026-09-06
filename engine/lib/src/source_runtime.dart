import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'analyzer/rule_analyzer.dart';
import 'analyzer/rule_evaluator.dart';
import 'models/comic_source.dart';
import 'models/content.dart';
import 'net/fetcher.dart';
import 'net/request.dart';

/// JS 取图钩子：由应用层注入 JS 执行环境（如 flutter_js），引擎保持纯 Dart。
/// [code] 为 JS 源码；[env] 预置变量（html/result = 页面文本、baseUrl 等）。
/// 返回 JS 求值结果（图片 URL 列表：换行分隔或 JSON 数组）；失败返回 null。
typedef JsHook = Future<String?> Function(String code, Map<String, dynamic> env);

/// 源运行时：把一个 [ComicSource] + [Fetcher] 变成可搜索、可阅读的接口。
class SourceRuntime {
  SourceRuntime({required this.source, required this.fetcher, this.jsHook});

  final ComicSource source;
  final Fetcher fetcher;
  final JsHook? jsHook;
  final _eval = const RuleEvaluator();

  static const _defaultUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  Map<String, String> get _headers => {
        'User-Agent': _defaultUa,
        ...source.headers,
      };

  /// 内容规则是否为 JS 形态（`$` 前缀、getImgList、@js: 尾缀）。
  /// 注意排除 jsonpath（`$.` 开头）与 Dart/JS 模板插值形态。
  static bool _looksLikeJs(String rule) {
    final r = rule.trim();
    if (r.startsWith(r'$.') || r.startsWith('\${')) return false;
    return r.startsWith(r'$') ||
        r.contains('getImgList') ||
        r.startsWith('@js:') ||
        r.startsWith('{{');
  }

  String _absUrl(String base, String v) {
    final u = v.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return Uri.parse(base).resolve(u).toString();
  }

  /// 规则 URL（可含 ppcat `@` POST/请求头语法）→ 绝对化后的完整请求。
  SourceRequest _request(String ruleUrl) {
    final req = parseRuleUrl(ruleUrl, headers: _headers);
    final abs = _absUrl(source.url, req.url);
    return SourceRequest(
        url: abs, method: req.method, body: req.body, headers: req.headers);
  }

  Future<dynamic> _fetchDoc(SourceRequest req) async {
    final bytes = await fetcher.send(req);
    final text = utf8.decode(bytes, allowMalformed: true);
    return _parseDoc(text);
  }

  dynamic _parseDoc(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return jsonDecode(text);
    }
    return html_parser.parse(text);
  }

  /// 搜索。返回分页结果（含源规则给的下一页链接，若有）。
  Future<Paged<Book>> search(String keyword, {int page = 1, String? nextUrl}) async {
    if (source.rules.searchUrl.isEmpty && nextUrl == null) {
      throw StateError('源 ${source.name} 未配置 searchUrl');
    }
    final key = Uri.encodeComponent(keyword);
    final req = nextUrl != null
        ? _request(nextUrl)
        : _request(renderUrlTemplate(source.rules.searchUrl, {
            'key': key,
            'keyword': key,
            'searchKey': key,
            'page': '$page',
            'searchPage': '$page',
            'pageSize': '20',
          }));
    return _fetchBooks(
      req,
      listRule: source.rules.searchList,
      nameRule: source.rules.searchName,
      authorRule: source.rules.searchAuthor,
      coverRule: source.rules.searchCoverUrl,
      introduceRule: source.rules.searchIntroduce,
      kindRule: source.rules.searchKind,
      lastChapterRule: source.rules.searchLastChapter,
      updateTimeRule: source.rules.searchUpdateTime,
      bookUrlRule: source.rules.searchBookUrl,
      nextRule: source.rules.searchUrlNext,
    );
  }

  /// 发现页（exploreUrl；支持多入口 `名称::url\n` 行格式）。
  List<(String, String)> exploreEntries() {
    final out = <(String, String)>[];
    var raw = source.rules.findUrl;
    if (raw.isEmpty) raw = source.rules.exploreUrl;
    if (raw.isEmpty) return out;
    for (final line in raw.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final sep = l.indexOf('::');
      if (sep > 0) {
        out.add((l.substring(0, sep).trim(), l.substring(sep + 2).trim()));
      } else {
        out.add(('发现', l));
      }
    }
    return out;
  }

  Future<Paged<Book>> explore(String entryUrl, {int page = 1, String? nextUrl}) async {
    final req = nextUrl != null
        ? _request(nextUrl)
        : _request(renderUrlTemplate(entryUrl, {
            'page': '$page',
            'searchPage': '$page',
          }));
    // ppcat 约定：发现页无独立规则时复用搜索规则
    final r = source.rules;
    final useFind = r.findList.isNotEmpty;
    return _fetchBooks(
      req,
      listRule: useFind ? r.findList : r.searchList,
      nameRule: useFind ? r.findName : r.searchName,
      authorRule: useFind ? r.findAuthor : r.searchAuthor,
      coverRule: useFind ? r.findCoverUrl : r.searchCoverUrl,
      introduceRule: useFind ? r.findIntroduce : r.searchIntroduce,
      kindRule: useFind ? r.findKind : r.searchKind,
      lastChapterRule: useFind ? r.findLastChapter : r.searchLastChapter,
      updateTimeRule: useFind ? r.findUpdateTime : r.searchUpdateTime,
      bookUrlRule: useFind ? r.findBookUrl : r.searchBookUrl,
      nextRule: '',
    );
  }

  /// 详情 + 章节列表。
  Future<(Book, List<Chapter>)> detail(String bookUrl) async {
    final doc = await _fetchDoc(_request(bookUrl));
    final r = source.rules;
    String? evalFirst(String rule, String fallbackRule) {
      if (rule.isNotEmpty) return _eval.evalFirst(doc, RuleAnalyzer(rule).parse());
      if (fallbackRule.isNotEmpty) return _eval.evalFirst(doc, RuleAnalyzer(fallbackRule).parse());
      return null;
    }
    final book = Book(
      sourceId: source.id,
      name: evalFirst(r.bookName, r.searchName) ?? '',
      author: evalFirst(r.bookAuthor, r.searchAuthor) ?? '',
      kind: evalFirst(r.bookKind, r.searchKind) ?? '',
      coverUrl: _absUrl(bookUrl, evalFirst(r.bookCoverUrl, r.searchCoverUrl) ?? ''),
      introduce: evalFirst(r.bookIntroduce, r.searchIntroduce) ?? '',
      lastChapter: evalFirst(r.bookLastChapter, r.searchLastChapter) ?? '',
      updateTime: evalFirst(r.bookUpdateTime, r.searchUpdateTime) ?? '',
      bookUrl: bookUrl,
    );

    final chapters = <Chapter>[];
    if (r.chapterList.isNotEmpty) {
      var pageUrl = bookUrl;
      var doc2 = doc; // 首页复用详情 doc，避免重复抓取
      final seen = <String>{};
      // ruleChapterUrlNext：章节列表翻页（legado/ppcat 语义，逐页追加并按链接去重）
      for (var page = 0; page < 20 && pageUrl.isNotEmpty; page++) {
        final items = _eval.evalNodes(doc2, RuleAnalyzer(r.chapterList).parse());
        var added = 0;
        for (final item in items) {
          String pick(String rule) =>
              rule.isEmpty ? '' : (_eval.evalFirst(item, RuleAnalyzer(rule).parse()) ?? '');
          final chUrl = _absUrl(pageUrl, pick(r.chapterUrl));
          if (chUrl.isEmpty || !seen.add(chUrl)) continue;
          chapters.add(Chapter(
            title: pick(r.chapterName),
            url: chUrl,
            coverUrl: _absUrl(pageUrl, pick(r.chapterCoverUrl)),
            time: pick(r.chapterTime),
            group: pick(r.chapterGroup),
          ));
          added++;
        }
        if (r.chapterUrlNext.isEmpty || (added == 0 && page > 0)) break;
        final next =
            _eval.evalFirst(doc2, RuleAnalyzer(r.chapterUrlNext).parse()) ?? '';
        final absNext = _absUrl(pageUrl, next.trim());
        if (absNext.isEmpty || absNext == pageUrl) break;
        pageUrl = absNext;
        doc2 = await _fetchDoc(_request(pageUrl));
      }
    }
    return (book, chapters);
  }

  /// 章节图片列表（跟随 contentUrlNext 翻页）。
  /// 内容规则为 JS 形态且注入了 [jsHook] 时，规则求值失败会回退 JS 执行。
  Future<List<String>> images(String chapterUrl, {int maxPages = 10}) async {
    final r = source.rules;
    if (r.contentUrl.isEmpty) return const [];
    final out = <String>[];
    var url = chapterUrl;
    for (var i = 0; i < maxPages && url.isNotEmpty; i++) {
      final req = _request(url);
      final bytes = await fetcher.send(req);
      final text = utf8.decode(bytes, allowMalformed: true);
      final doc = _parseDoc(text);
      final urls = _eval.eval(doc, RuleAnalyzer(r.contentUrl).parse());
      var page = urls.map((u) => _absUrl(url, u)).toList();
      if (page.isEmpty && jsHook != null && _looksLikeJs(r.contentUrl)) {
        page = await _evalJsImages(r.contentUrl, text, url);
      }
      out.addAll(page);
      if (r.contentUrlNext.isEmpty) break;
      final next = _eval.evalFirst(doc, RuleAnalyzer(r.contentUrlNext).parse()) ?? '';
      url = _absUrl(url, next.trim());
    }
    return out;
  }

  /// 执行 JS 取图规则：剥掉 `$`/`@js:` 前缀与 `@Header:{...}` 尾缀后交给钩子；
  /// ppcat 契约：全局变量 `html`/`result` 为页面文本，若定义了 getImgList
  /// 但代码未显式调用，则补 `getImgList(html)` 调用；结果按换行/JSON 数组解析。
  Future<List<String>> _evalJsImages(String rule, String pageText, String baseUrl) async {
    var code = rule.trim();
    if (code.startsWith('@js:')) code = code.substring(4);
    if (code.startsWith(r'$') && !code.startsWith(r'$.') && !code.startsWith('\${')) {
      code = code.substring(1);
    }
    final headerM = RegExp(r'@Header:\s*(\{[\s\S]*\})\s*$').firstMatch(code);
    if (headerM != null) code = code.substring(0, headerM.start).trim();
    if (RegExp(r'function\s+getImgList\s*\(').hasMatch(code) &&
        !RegExp(r'getImgList\s*\([^)]*\)\s*;?\s*$').hasMatch(code)) {
      code = '$code\ngetImgList(html);';
    }
    String? result;
    try {
      result = await jsHook!(code, {
        'html': pageText,
        'result': pageText,
        'baseUrl': baseUrl,
        'key': '',
        'page': '',
      });
    } catch (_) {
      return const [];
    }
    if (result == null || result.trim().isEmpty) return const [];
    final s = result.trim();
    final raw = <String>[];
    if (s.startsWith('[') || s.startsWith('{')) {
      try {
        final j = jsonDecode(s);
        if (j is List) {
          raw.addAll(j.map((e) => e is Map ? (e['url'] ?? e['src'] ?? '').toString() : e.toString()));
        } else if (j is Map) {
          raw.add((j['url'] ?? j['src'] ?? '').toString());
        }
      } catch (_) {}
    }
    if (raw.isEmpty) {
      raw.addAll(s
          .split(RegExp(r'[\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty));
    }
    return raw.map((u) => _absUrl(baseUrl, u)).where((u) => u.isNotEmpty).toList();
  }

  /// 内容规则尾部 `@Header:{...}` 解析出的图片请求头（防盗链源用）。
  /// 空表 = 未指定；`Referer:none` 语义为不带 Referer，交给调用方处理。
  Map<String, String> get imageRequestHeaders {
    final m = RegExp(r'@Header:\s*(\{[\s\S]*\})\s*$').firstMatch(source.rules.contentUrl);
    if (m == null) return const {};
    final h = RuleAnalyzer.lenientJsonMap(m.group(1)!);
    h.removeWhere((k, v) => v.toLowerCase() == 'none');
    return h;
  }

  static final _tplHole = RegExp(r'\{\$([^{}]+)\}');

  /// `https://host/topic/{$.id}/` 形式的字面模板：逐洞对条目求 jsonpath 并代入。
  String _evalTemplateRule(String rule, dynamic item) {
    return rule.replaceAllMapped(_tplHole, (m) {
      final inner = m.group(1)!.trim();
      final holeRule = RuleAnalyzer(inner.startsWith('\$') ? inner : '\$$inner').parse();
      return _eval.evalFirst(item, holeRule) ?? '';
    });
  }

  Future<Paged<Book>> _fetchBooks(
    SourceRequest req, {
    required String listRule,
    required String nameRule,
    String? authorRule,
    String? coverRule,
    String? introduceRule,
    String? kindRule,
    String? lastChapterRule,
    String? updateTimeRule,
    String? bookUrlRule,
    required String nextRule,
  }) async {
    if (listRule.isEmpty) {
      throw StateError('源 ${source.name} 未配置列表规则');
    }
    final url = req.url;
    final doc = await _fetchDoc(req);
    // `-` 前缀 = 倒序（legado 语义）
    var ruleStr = listRule;
    var reverse = false;
    if (ruleStr.startsWith('-')) {
      reverse = true;
      ruleStr = ruleStr.substring(1);
    }
    final rule = RuleAnalyzer(ruleStr).parse();
    final items = _eval.evalNodes(doc, rule);
    final ordered = reverse ? items.reversed.toList() : items;

    String pick(dynamic item, String r, {bool abs = false}) {
      if (r.isEmpty || item is String) return item is String ? item : '';
      // 字面模板内嵌 jsonpath（ppcat `{$.id}` → https://host/topic/3095/）
      var v = r.contains(r'{$')
          ? _evalTemplateRule(r, item)
          : (_eval.evalFirst(item, RuleAnalyzer(r).parse()) ?? '');
      if (abs) v = _absUrl(url, v);
      return v;
    }

    final books = ordered.map((item) {
      return Book(
        sourceId: source.id,
        name: pick(item, nameRule),
        author: pick(item, authorRule ?? ''),
        coverUrl: pick(item, coverRule ?? '', abs: true),
        introduce: pick(item, introduceRule ?? ''),
        kind: pick(item, kindRule ?? ''),
        lastChapter: pick(item, lastChapterRule ?? ''),
        updateTime: pick(item, updateTimeRule ?? ''),
        bookUrl: pick(item, bookUrlRule ?? '', abs: true),
      );
    }).where((b) => b.name.isNotEmpty || b.bookUrl.isNotEmpty).toList();

    String? next;
    if (nextRule.isNotEmpty) {
      final n = _eval.evalFirst(doc, RuleAnalyzer(nextRule).parse()) ?? '';
      final abs = _absUrl(url, n.trim());
      if (abs.isNotEmpty && abs != url) next = abs;
    }
    return Paged(books, nextPage: next);
  }
}
