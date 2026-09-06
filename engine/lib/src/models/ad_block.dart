import 'dart:convert';

/// 广告拦截规则：按正则过滤图片/书源 URL 与书名。
///
/// 兼容格式族（键名宽松，坏条目跳过）：
/// ```json
/// {
///   "enabled": true,
///   "urlRules":  ["(?i)adserver", ".*\\.abc\\.net/img/.*"],
///   "nameRules": ["预告|广告|插页"]
/// }
/// ```
/// - JSON 键别名：`adUrl`/`adList`/`urls`/`blockUrls` → URL 规则；
///   `adName`/`nameList` → 名称规则；规则为正则字符串，普通域名即子串匹配。
/// - 顶层字符串数组 → 整体视为 URL 规则。
/// - 纯文本（hosts / adblock 风格 txt）：每行一条；`#`/`!` 注释跳过；
///   `0.0.0.0 x.com`/`127.0.0.1 x.com`/`||x.com^` 均提取域名，整域拦截。
///
/// 注：皮皮喵原版广告规则为闭源 APK 内部格式、无公开文档；本解析器按
/// 生态惯例宽容设计，拿到真实样本后可直接映射。
class AdBlockRules {
  AdBlockRules({required this.enabled, required this.urlRules, required this.nameRules});

  final bool enabled;
  final List<RegExp> urlRules;
  final List<RegExp> nameRules;

  static const _urlKeys = ['urlRules', 'adUrl', 'adList', 'urls', 'blockUrls', 'urlRule'];
  static const _nameKeys = ['nameRules', 'adName', 'nameList'];

  factory AdBlockRules.fromJson(Map<String, dynamic> j) {
    final enabled = j['enabled'] is bool ? j['enabled'] as bool : true;
    List<RegExp> urls = const [];
    for (final k in _urlKeys) {
      final v = _parseList(j[k]);
      if (v.isNotEmpty) {
        urls = v;
        break;
      }
    }
    List<RegExp> names = const [];
    for (final k in _nameKeys) {
      final v = _parseList(j[k]);
      if (v.isNotEmpty) {
        names = v;
        break;
      }
    }
    return AdBlockRules(enabled: enabled, urlRules: urls, nameRules: names);
  }

  /// 解析文本：JSON（对象/数组）或纯文本 hosts/域名列表。
  /// 无法识别返回 null（调用方提示导入失败）。
  static AdBlockRules? tryParse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        final j = jsonDecode(t);
        if (j is Map<String, dynamic>) return AdBlockRules.fromJson(j);
        if (j is List) {
          // 纯规则数组视为 urlRules
          return AdBlockRules.fromJson({'urlRules': j});
        }
      } on FormatException {
        return null;
      }
      return null;
    }
    // 纯文本：hosts / adblock 风格域名列表
    final lines = _parseTextLines(t);
    if (lines.isEmpty) return null;
    return AdBlockRules.fromJson({'urlRules': lines});
  }

  /// hosts/adblock 文本行 → 域名正则：
  /// `#`/`!` 注释与空行跳过；`0.0.0.0 x.com` / `127.0.0.1 x.com` /
  /// `||x.com^` / `@@x.com`（白名单，跳过）/ 裸域名 `x.com`。
  static List<String> _parseTextLines(String text) {
    final out = <String>[];
    for (var raw in text.split(RegExp(r'[\n\r]+'))) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
      // adblock 白名单 @@ → 跳过（当前语义只支持黑名单）
      if (line.startsWith('@@')) continue;
      // `0.0.0.0 x.com` / `127.0.0.1 x.com`
      final host = RegExp(r'^(?:0\.0\.0\.0|127\.0\.0\.1)\s+(\S+)$').firstMatch(line);
      if (host != null) {
        out.add(_domainRule(host.group(1)!));
        continue;
      }
      // `||x.com^` / `||x.com/path^`
      final abp = RegExp(r'^\|\|([A-Za-z0-9.\-]+\.[A-Za-z]{2,})(\^.*)?$').firstMatch(line);
      if (abp != null) {
        out.add(_domainRule(abp.group(1)!));
        continue;
      }
      // 剩余行整体视为一条正则（ppcat 规则体系即 URL 正则）
      line = line.replaceAll(RegExp(r'\s+'), '');
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  /// 域名 → 正则：整域及其子域命中。
  static String _domainRule(String domain) =>
      '([A-Za-z0-9-]+\\.)*${RegExp.escape(domain)}';

  static List<RegExp> _parseList(dynamic v) {
    if (v is! List) return const [];
    final out = <RegExp>[];
    for (final e in v) {
      if (e is! String || e.trim().isEmpty) continue;
      try {
        out.add(RegExp(e, caseSensitive: false));
      } on FormatException {
        // 坏正则跳过
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'urlRules': urlRules.map((r) => r.pattern).toList(),
        'nameRules': nameRules.map((r) => r.pattern).toList(),
      };

  bool blocksImageUrl(String url) =>
      enabled && urlRules.any((r) => r.hasMatch(url));

  bool blocksName(String name) =>
      enabled && nameRules.any((r) => r.hasMatch(name));

  /// 过滤图片 URL 列表。
  List<String> filterImages(List<String> urls) =>
      enabled ? urls.where((u) => !blocksImageUrl(u)).toList() : urls;
}
