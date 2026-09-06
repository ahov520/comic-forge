import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'analyzer/rule_analyzer.dart';
import 'analyzer/rule_evaluator.dart';
import 'models/comic_source.dart';
import 'models/content.dart';
import 'net/fetcher.dart';

/// 源运行时：把一个 [ComicSource] + [Fetcher] 变成可搜索、可阅读的接口。
class SourceRuntime {
  SourceRuntime({required this.source, required this.fetcher});

  final ComicSource source;
  final Fetcher fetcher;
  final _eval = const RuleEvaluator();

  static const _defaultUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  Map<String, String> get _headers => {
        'User-Agent': _defaultUa,
        ...source.headers,
      };

  String _absUrl(String base, String v) {
    final u = v.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return Uri.parse(base).resolve(u).toString();
  }

  Future<dynamic> _fetchDoc(String url) async {
    final text = await fetcher.getString(url, headers: _headers);
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return jsonDecode(text);
    }
    return html_parser.parse(text);
  }

  /// 轻量探活：GET 源站点 url；没有则渲染 searchUrl 再 GET。不解析规则。
  Future<void> probe() async {
    var url = source.url.trim();
    if (url.isEmpty && source.rules.searchUrl.isNotEmpty) {
      url = _absUrl(
        source.url,
        renderUrlTemplate(source.rules.searchUrl, {
          'key': '1',
          'keyword': '1',
          'searchKey': '1',
          'page': '1',
          'searchPage': '1',
          'pageSize': '1',
        }),
      );
    }
    if (url.isEmpty) {
      throw StateError('源 ${source.name} 无可探测地址');
    }
    await fetcher.getString(url, headers: _headers);
  }

  /// 搜索。返回分页结果（含源规则给的下一页链接，若有）。
  Future<Paged<Book>> search(String keyword, {int page = 1, String? nextUrl}) async {
    if (source.rules.searchUrl.isEmpty && nextUrl == null) {
      throw StateError('源 ${source.name} 未配置 searchUrl');
    }
    final key = Uri.encodeComponent(keyword);
    final url = nextUrl ??
        _absUrl(source.url, renderUrlTemplate(source.rules.searchUrl, {
          'key': key,
          'keyword': key,
          'searchKey': key,
          'page': '$page',
          'searchPage': '$page',
          'pageSize': '20',
        }));
    return _fetchBooks(
      url,
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
    final url = nextUrl ??
        _absUrl(source.url, renderUrlTemplate(entryUrl, {
          'page': '$page',
          'searchPage': '$page',
        }));
    // ppcat 约定：发现页无独立规则时复用搜索规则
    final r = source.rules;
    final useFind = r.findList.isNotEmpty;
    return _fetchBooks(
      url,
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
    final doc = await _fetchDoc(bookUrl);
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
      final items = _eval.evalNodes(doc, RuleAnalyzer(r.chapterList).parse());
      for (final item in items) {
        String pick(String rule) =>
            rule.isEmpty ? '' : (_eval.evalFirst(item, RuleAnalyzer(rule).parse()) ?? '');
        chapters.add(Chapter(
          title: pick(r.chapterName),
          url: _absUrl(bookUrl, pick(r.chapterUrl)),
          coverUrl: _absUrl(bookUrl, pick(r.chapterCoverUrl)),
          time: pick(r.chapterTime),
          group: pick(r.chapterGroup),
        ));
      }
    }
    // TODO(Phase2+): ruleChapterUrlNext 翻页
    return (book, chapters);
  }

  /// 章节图片列表（跟随 contentUrlNext 翻页）。
  Future<List<String>> images(String chapterUrl, {int maxPages = 10}) async {
    final r = source.rules;
    if (r.contentUrl.isEmpty) return const [];
    final out = <String>[];
    var url = chapterUrl;
    for (var i = 0; i < maxPages && url.isNotEmpty; i++) {
      final doc = await _fetchDoc(url);
      final urls = _eval.eval(doc, RuleAnalyzer(r.contentUrl).parse());
      out.addAll(urls.map((u) => _absUrl(url, u)));
      if (r.contentUrlNext.isEmpty) break;
      final next = _eval.evalFirst(doc, RuleAnalyzer(r.contentUrlNext).parse()) ?? '';
      url = _absUrl(url, next.trim());
    }
    return out;
  }

  Future<Paged<Book>> _fetchBooks(
    String url, {
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
    final doc = await _fetchDoc(url);
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
      var v = _eval.evalFirst(item, RuleAnalyzer(r).parse()) ?? '';
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
