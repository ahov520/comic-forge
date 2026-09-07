/// 漫画源的一组规则（嵌套视图）。
///
/// ppcat 的 JSON 里规则是平铺键（如 `ruleSearchList`），载入时由
/// [ComicSource.fromPpcatFlat] 归一到本模型；引擎只认嵌套视图。
class RuleSet {
  String searchUrl = '';
  String exploreUrl = '';

  String searchList = '', searchName = '', searchAuthor = '', searchCoverUrl = '';
  String searchIntroduce = '', searchKind = '', searchLastChapter = '', searchUpdateTime = '';
  String searchBookUrl = '', searchUrlNext = '';

  String findList = '', findName = '', findAuthor = '', findCoverUrl = '';
  String findIntroduce = '', findKind = '', findLastChapter = '', findUpdateTime = '';
  String findBookUrl = '', findUrl = '';

  String bookInit = '', bookName = '', bookAuthor = '', bookKind = '';
  String bookCoverUrl = '', bookLastChapter = '', bookIntroduce = '', bookUpdateTime = '';

  String chapterList = '', chapterName = '', chapterCoverUrl = '', chapterTime = '';
  String chapterGroup = '', chapterUrl = '', chapterUrlNext = '', chapterInit = '';

  String contentInit = '', contentUrl = '', contentUrlNext = '', contentWebUrl = '';

  /// 平铺键名 → 本模型字段名 的映射（按真实 .mh_rules 样本校准，2026-09）。
  /// 注意：ruleBookContent 是取图规则（CSS 或 `$js`），ruleContentUrl 是
  /// 章节链接规则；ruleChapterUrl 仅在 chapterUrl 仍为空时兼容回填。
  static const Map<String, String> ppcatFlatKeys = {
    // Snapshot / ppcat 平铺源用 ruleSearchUrl；嵌套/Track A 用 searchUrl。
    // 两者都映射到嵌套 searchUrl，缺一则聚合搜索会滤掉整源。
    'ruleSearchUrl': 'searchUrl',
    'searchUrl': 'searchUrl',
    'exploreUrl': 'exploreUrl',
    'ruleSearchList': 'searchList',
    'ruleSearchName': 'searchName',
    'ruleSearchAuthor': 'searchAuthor',
    'ruleSearchCoverUrl': 'searchCoverUrl',
    'ruleSearchIntroduce': 'searchIntroduce',
    'ruleSearchIntro': 'searchIntroduce',
    'ruleSearchKind': 'searchKind',
    'ruleSearchLastChapter': 'searchLastChapter',
    'ruleSearchUpdateTime': 'searchUpdateTime',
    'ruleSearchNoteUrl': 'searchBookUrl',
    'ruleSearchUrlNext': 'searchUrlNext',
    'ruleFindList': 'findList',
    'ruleFindName': 'findName',
    'ruleFindAuthor': 'findAuthor',
    'ruleFindCoverUrl': 'findCoverUrl',
    'ruleFindIntroduce': 'findIntroduce',
    'ruleFindKind': 'findKind',
    'ruleFindLastChapter': 'findLastChapter',
    'ruleFindUpdateTime': 'findUpdateTime',
    'ruleFindNoteUrl': 'findBookUrl',
    'ruleFindUrl': 'findUrl',
    'ruleBookInit': 'bookInit',
    'ruleBookName': 'bookName',
    'ruleBookAuthor': 'bookAuthor',
    'ruleBookKind': 'bookKind',
    'ruleCoverUrl': 'bookCoverUrl',
    'ruleBookLastChapter': 'bookLastChapter',
    'ruleIntroduce': 'bookIntroduce',
    'ruleBookUpdateTime': 'bookUpdateTime',
    'ruleChapterList': 'chapterList',
    'ruleChapterName': 'chapterName',
    'ruleChapterCoverUrl': 'chapterCoverUrl',
    'ruleChapterTime': 'chapterTime',
    'ruleChapterGroup': 'chapterGroup',
    'ruleContentUrl': 'chapterUrl',
    'ruleChapterUrlNext': 'chapterUrlNext',
    'ruleChapterInit': 'chapterInit',
    'ruleContentInit': 'contentInit',
    'ruleBookContent': 'contentUrl',
    'ruleContentUrlNext': 'contentUrlNext',
    'ruleContentWebUrl': 'contentWebUrl',
  };

  Map<String, dynamic> toJson() => {
        if (searchUrl.isNotEmpty) 'searchUrl': searchUrl,
        if (exploreUrl.isNotEmpty) 'exploreUrl': exploreUrl,
        if (searchList.isNotEmpty) 'searchList': searchList,
        if (searchName.isNotEmpty) 'searchName': searchName,
        if (searchAuthor.isNotEmpty) 'searchAuthor': searchAuthor,
        if (searchCoverUrl.isNotEmpty) 'searchCoverUrl': searchCoverUrl,
        if (searchIntroduce.isNotEmpty) 'searchIntroduce': searchIntroduce,
        if (searchKind.isNotEmpty) 'searchKind': searchKind,
        if (searchLastChapter.isNotEmpty) 'searchLastChapter': searchLastChapter,
        if (searchUpdateTime.isNotEmpty) 'searchUpdateTime': searchUpdateTime,
        if (searchBookUrl.isNotEmpty) 'searchBookUrl': searchBookUrl,
        if (searchUrlNext.isNotEmpty) 'searchUrlNext': searchUrlNext,
        if (findList.isNotEmpty) 'findList': findList,
        if (findName.isNotEmpty) 'findName': findName,
        if (findAuthor.isNotEmpty) 'findAuthor': findAuthor,
        if (findCoverUrl.isNotEmpty) 'findCoverUrl': findCoverUrl,
        if (findIntroduce.isNotEmpty) 'findIntroduce': findIntroduce,
        if (findKind.isNotEmpty) 'findKind': findKind,
        if (findLastChapter.isNotEmpty) 'findLastChapter': findLastChapter,
        if (findUpdateTime.isNotEmpty) 'findUpdateTime': findUpdateTime,
        if (findBookUrl.isNotEmpty) 'findBookUrl': findBookUrl,
        if (findUrl.isNotEmpty) 'findUrl': findUrl,
        if (bookInit.isNotEmpty) 'bookInit': bookInit,
        if (bookName.isNotEmpty) 'bookName': bookName,
        if (bookAuthor.isNotEmpty) 'bookAuthor': bookAuthor,
        if (bookKind.isNotEmpty) 'bookKind': bookKind,
        if (bookCoverUrl.isNotEmpty) 'bookCoverUrl': bookCoverUrl,
        if (bookLastChapter.isNotEmpty) 'bookLastChapter': bookLastChapter,
        if (bookIntroduce.isNotEmpty) 'bookIntroduce': bookIntroduce,
        if (bookUpdateTime.isNotEmpty) 'bookUpdateTime': bookUpdateTime,
        if (chapterList.isNotEmpty) 'chapterList': chapterList,
        if (chapterName.isNotEmpty) 'chapterName': chapterName,
        if (chapterCoverUrl.isNotEmpty) 'chapterCoverUrl': chapterCoverUrl,
        if (chapterTime.isNotEmpty) 'chapterTime': chapterTime,
        if (chapterGroup.isNotEmpty) 'chapterGroup': chapterGroup,
        if (chapterUrl.isNotEmpty) 'chapterUrl': chapterUrl,
        if (chapterUrlNext.isNotEmpty) 'chapterUrlNext': chapterUrlNext,
        if (chapterInit.isNotEmpty) 'chapterInit': chapterInit,
        if (contentInit.isNotEmpty) 'contentInit': contentInit,
        if (contentUrl.isNotEmpty) 'contentUrl': contentUrl,
        if (contentUrlNext.isNotEmpty) 'contentUrlNext': contentUrlNext,
        if (contentWebUrl.isNotEmpty) 'contentWebUrl': contentWebUrl,
      };

  void apply(Map<String, String> fields) {
    final map = <String, void Function(String)>{
      'searchUrl': (v) => searchUrl = v,
      'exploreUrl': (v) => exploreUrl = v,
      'searchList': (v) => searchList = v,
      'searchName': (v) => searchName = v,
      'searchAuthor': (v) => searchAuthor = v,
      'searchCoverUrl': (v) => searchCoverUrl = v,
      'searchIntroduce': (v) => searchIntroduce = v,
      'searchKind': (v) => searchKind = v,
      'searchLastChapter': (v) => searchLastChapter = v,
      'searchUpdateTime': (v) => searchUpdateTime = v,
      'searchBookUrl': (v) => searchBookUrl = v,
      'searchUrlNext': (v) => searchUrlNext = v,
      'findList': (v) => findList = v,
      'findName': (v) => findName = v,
      'findAuthor': (v) => findAuthor = v,
      'findCoverUrl': (v) => findCoverUrl = v,
      'findIntroduce': (v) => findIntroduce = v,
      'findKind': (v) => findKind = v,
      'findLastChapter': (v) => findLastChapter = v,
      'findUpdateTime': (v) => findUpdateTime = v,
      'findBookUrl': (v) => findBookUrl = v,
      'findUrl': (v) => findUrl = v,
      'bookInit': (v) => bookInit = v,
      'bookName': (v) => bookName = v,
      'bookAuthor': (v) => bookAuthor = v,
      'bookKind': (v) => bookKind = v,
      'bookCoverUrl': (v) => bookCoverUrl = v,
      'bookLastChapter': (v) => bookLastChapter = v,
      'bookIntroduce': (v) => bookIntroduce = v,
      'bookUpdateTime': (v) => bookUpdateTime = v,
      'chapterList': (v) => chapterList = v,
      'chapterName': (v) => chapterName = v,
      'chapterCoverUrl': (v) => chapterCoverUrl = v,
      'chapterTime': (v) => chapterTime = v,
      'chapterGroup': (v) => chapterGroup = v,
      'chapterUrl': (v) => chapterUrl = v,
      'chapterUrlNext': (v) => chapterUrlNext = v,
      'chapterInit': (v) => chapterInit = v,
      'contentInit': (v) => contentInit = v,
      'contentUrl': (v) => contentUrl = v,
      'contentUrlNext': (v) => contentUrlNext = v,
      'contentWebUrl': (v) => contentWebUrl = v,
    };
    fields.forEach((k, v) {
      final setter = map[k];
      if (setter != null && v.isNotEmpty) setter(v);
    });
  }
}

/// 一个漫画源。
class ComicSource {
  ComicSource({
    required this.id,
    this.name = '',
    this.group = '',
    this.icon = '',
    this.url = '',
    this.comment = '',
    this.enabled = true,
    this.weight = 0,
    Map<String, String>? headers,
    RuleSet? rules,
  })  : headers = headers ?? {},
        rules = rules ?? RuleSet();

  String id;
  String name;
  String group;
  String icon;
  String url;
  String comment;
  bool enabled;
  int weight;
  Map<String, String> headers;
  RuleSet rules;

  // ---- 源健康（app 侧回报，随源持久化）----
  /// 最近一次失败原因（成功时清空）。
  String lastError = '';
  /// 最近失败时间（epoch 毫秒；0 = 从未失败）。
  int lastFailedAt = 0;
  /// 连续失败计数（成功清零；≥3 视为失效候选，可一键禁用）。
  int failCount = 0;
  /// 最近成功时间（epoch 毫秒；0 = 从未成功）。
  int lastOkAt = 0;

  /// 失效候选：连续失败 ≥3 次。
  bool get isUnhealthy => failCount >= 3;

  /// 原始 JSON（保持往返保真，未知键不丢）。
  Map<String, dynamic> raw = {};

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name.isNotEmpty) 'name': name,
        if (group.isNotEmpty) 'group': group,
        if (icon.isNotEmpty) 'icon': icon,
        if (url.isNotEmpty) 'url': url,
        if (comment.isNotEmpty) 'comment': comment,
        'enabled': enabled,
        if (weight != 0) 'weight': weight,
        if (headers.isNotEmpty) 'headers': headers,
        'rules': rules.toJson(),
        if (lastError.isNotEmpty) 'lastError': lastError,
        if (lastFailedAt != 0) 'lastFailedAt': lastFailedAt,
        if (failCount != 0) 'failCount': failCount,
        if (lastOkAt != 0) 'lastOkAt': lastOkAt,
      };

  /// 从明文仓库（Track A）JSON 构建。
  static ComicSource fromJson(Map<String, dynamic> j) {
    final s = ComicSource(
      id: (j['id'] ?? j['sourceUrl'] ?? j['url'] ?? j['sourceName'] ?? '') as String,
      name: (j['name'] ?? j['sourceName'] ?? '') as String,
      group: (j['group'] ?? j['sourceGroup'] ?? '') as String,
      icon: (j['icon'] ?? j['sourceIcon'] ?? '') as String,
      url: (j['url'] ?? j['sourceUrl'] ?? '') as String,
      comment: (j['comment'] ?? j['sourceComment'] ?? '') as String,
      enabled: (j['enabled'] ?? true) as bool,
      weight: (j['weight'] ?? 0) is int ? (j['weight'] ?? 0) as int : 0,
    );
    final h = j['headers'];
    if (h is Map) {
      h.forEach((k, v) => s.headers[k.toString()] = v.toString());
    }
    // 源健康（容错：老快照/手改 JSON 里可能是错型）
    s.lastError = j['lastError'] is String ? j['lastError'] as String : '';
    s.lastFailedAt = j['lastFailedAt'] is int ? j['lastFailedAt'] as int : 0;
    s.failCount = j['failCount'] is int ? j['failCount'] as int : 0;
    s.lastOkAt = j['lastOkAt'] is int ? j['lastOkAt'] as int : 0;
    s.raw = Map<String, dynamic>.from(j);
    final r = j['rules'];
    if (r is Map) {
      r.forEach((k, v) {
        if (v is String) s._setRule(k, v);
      });
    }
    // 也允许规则直接平铺在源 JSON 顶层（嵌套 rules 缺省时）
    j.forEach((k, v) {
      if (v is String && RuleSet.ppcatFlatKeys.containsKey(k)) {
        s._setRule(RuleSet.ppcatFlatKeys[k]!, v);
      }
    });
    s._applyChapterUrlFallback(j);
    return s;
  }

  /// 从 ppcat 平铺键 JSON 构建（兼容导入，含 bookSource* 头部字段）。
  static ComicSource fromPpcatFlat(Map<String, dynamic> j) {
    final s = ComicSource.fromJson({
      'id': j['ruleId'] ?? j['bookSourceUrl'] ?? j['sourceUrl'] ?? '',
      'name': j['sourceName'] ?? j['bookSourceName'] ?? j['name'] ?? '',
      'group': j['sourceGroup'] ?? j['bookSourceGroup'] ?? '',
      'icon': j['sourceIcon'] ?? '',
      'url': j['sourceUrl'] ?? j['bookSourceUrl'] ?? '',
      'comment': j['sourceComment'] ?? '',
      'enabled': j['enabled'] ?? true,
      'weight': j['weight'] ?? 0,
    });
    final ua = j['httpUserAgent'];
    if (ua is String && ua.isNotEmpty) s.headers['User-Agent'] = ua;
    final h = j['headers'];
    if (h is Map) {
      h.forEach((k, v) {
        if (v == null) return;
        final key = k.toString();
        final val = v.toString();
        if (key.isNotEmpty && val.isNotEmpty) s.headers[key] = val;
      });
    }
    final fields = <String, String>{};
    RuleSet.ppcatFlatKeys.forEach((flat, nested) {
      final v = j[flat];
      if (v is String && v.isNotEmpty) fields[nested] = v;
    });
    s.rules.apply(fields);
    s._applyChapterUrlFallback(j);
    // raw 保存原始平铺 JSON（此前误存合成 map，导出/分享会丢规则）
    s.raw = Map<String, dynamic>.from(j);
    return s;
  }

  void _applyChapterUrlFallback(Map<String, dynamic> j) {
    // 双字段源的 ruleChapterUrl 可能是展开目录入口，不能覆盖逐章链接。
    final fallback = j['ruleChapterUrl'];
    if (rules.chapterUrl.isEmpty && fallback is String) {
      _setRule('chapterUrl', fallback);
    }
  }

  void _setRule(String nestedKey, String value) {
    rules.apply({nestedKey: value});
  }
}
