import 'dart:convert';

import '../models/comic_source.dart';

/// H-Viewer / ExView 站点规则 JSON → [ComicSource] 适配器。
///
/// H-Viewer 规则结构（见 ghostgzt/H-Viewer-Sites 样例）：
/// ```json
/// {
///   "title": "站点名", "indexUrl": "...", "searchUrl": {"path": "...", "keywords": "searchKey"},
///   "categories": [{"title":"分类","url":"..."}],
///   "indexRule": {"item":{"selector":"..."},"title":{"selector":"...","fun":"text"},
///                 "cover":{"selector":"img","fun":"attr","param":"src"}},
///   "galleryRule": {"title":{...}, "pictureRule":{"item":{...},"url":{...},"thumbnail":{...}}}
/// }
/// ```
class HViewerAdapter {
  /// 转换单个站点规则 JSON。
  static ComicSource convert(Map<String, dynamic> j) {
    final rules = RuleSet()
      ..searchUrl = _searchUrl(j)
      ..exploreUrl = _exploreEntries(j);

    final index = j['indexRule'];
    if (index is Map<String, dynamic>) {
      rules
        ..findList = _selectorOf(index['item'])
        ..findName = _field(index['title'])
        ..findAuthor = _field(index['uploader'])
        ..findCoverUrl = _field(index['cover'])
        ..findIntroduce = _field(index['tags'])
        ..findUpdateTime = _field(index['datetime'])
        ..findBookUrl = _field(index['idCode']);
    }
    final gallery = j['galleryRule'];
    if (gallery is Map<String, dynamic>) {
      // 图片页规则挂在 chapter/content 位：pictureRule.item 为分页 item，
      // url 为大图，thumbnail 为缩略图；页码在 pictureUrl/pictureUrlRule。
      final pic = gallery['pictureRule'];
      if (pic is Map<String, dynamic>) {
        rules
          ..contentUrl = _field(pic['url'])
          ..contentUrlNext = _field(pic['pictureUrl']) ;
        if (rules.contentUrl.isEmpty) {
          rules.contentUrl = _field(pic['thumbnail']);
        }
      }
    }
    return ComicSource(
      id: 'hviewer-${j['sid'] ?? j['title']}',
      name: (j['title'] ?? '') as String,
      group: 'H-Viewer',
      url: (j['baseUrl'] ?? _firstUrl(j)) as String,
      comment: (j['description'] ?? '') as String,
      rules: rules,
    );
  }

  /// 转换 H-Viewer-Sites 的 sites.json（分组索引结构）。
  static List<ComicSource> convertIndex(
    Map<String, dynamic> indexJson,
    String Function(String jsonUrl) siteRuleOf,
  ) {
    final out = <ComicSource>[];
    // sites.json 是 [{cid,title,sites:[{sid,title,json,...}]}] 的引用结构，
    // 真正的规则体在 json 指向的站点规则文件里——由 [siteRuleOf] 提供。
    // 这里仅转换内联的规则（若有）。
    return out;
  }

  // ---------- 内部 ----------

  static String _searchUrl(Map<String, dynamic> j) {
    final s = j['searchUrl'];
    if (s is String) return s;
    if (s is Map<String, dynamic>) {
      final path = (s['path'] ?? '') as String;
      final kw = (s['keywords'] ?? 'searchKey') as String;
      // H-Viewer: path 内含 {keywords:...} 占位符则原样保留
      if (path.contains('{')) return path;
      return '$path?$kw={{key}}';
    }
    return '';
  }

  static String _exploreEntries(Map<String, dynamic> j) {
    final cats = j['categories'];
    if (cats is! List) return '';
    final buf = StringBuffer();
    for (final c in cats) {
      if (c is Map<String, dynamic> && c['url'] is String) {
        buf.writeln('${c['title']}::${c['url']}');
      }
    }
    return buf.toString().trim();
  }

  static String _firstUrl(Map<String, dynamic> j) {
    final cats = j['categories'];
    if (cats is List && cats.isNotEmpty) {
      final c = cats.first;
      if (c is Map<String, dynamic>) return Uri.parse(c['url'] as String? ?? '').origin;
    }
    return '';
  }

  static String _selectorOf(dynamic field) {
    if (field is Map<String, dynamic>) return (field['selector'] ?? '') as String;
    if (field is String) return field;
    return '';
  }

  /// 字段描述 → 我们的规则串。
  static String _field(dynamic field) {
    if (field == null) return '';
    if (field is String) return field;
    if (field is! Map<String, dynamic>) return '';
    var sel = (field['selector'] ?? '') as String;
    if (sel.isEmpty) return '';
    var out = sel;
    final fun = (field['fun'] ?? 'text') as String;
    final param = field['param'];
    out = '$out@${param ?? fun}';
    if (param != null) {
      // fun=attr 时 @param 已是属性名；text/html 等保留
      if (fun != 'attr') out = '$sel@$fun';
    }
    final regex = field['regex'];
    if (regex is String && regex.isNotEmpty) {
      final rep = field['replacement'];
      out = '$out##$regex${rep == null ? '' : '##$rep'}';
    }
    return out;
  }
}

/// 从 JSON 文本直接转换（容忍 BOM）。
ComicSource? hviewerFromJsonText(String text) {
  try {
    final j = jsonDecode(text);
    if (j is Map<String, dynamic>) return HViewerAdapter.convert(j);
  } on FormatException {
    return null;
  }
  return null;
}
