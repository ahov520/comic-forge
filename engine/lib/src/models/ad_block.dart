import 'dart:convert';

/// 广告拦截规则：按正则过滤图片/书源 URL 与书名。
///
/// 兼容格式（键名宽松，坏条目跳过）：
/// ```json
/// {
///   "enabled": true,
///   "urlRules":  ["(?i)adserver", ".*\\.abc\\.net/img/.*"],
///   "nameRules": ["预告|广告|插页"]
/// }
/// ```
/// 也接受 `adUrl` / `adName` 作为别名；规则为正则字符串，普通域名即子串匹配。
class AdBlockRules {
  AdBlockRules({required this.enabled, required this.urlRules, required this.nameRules});

  final bool enabled;
  final List<RegExp> urlRules;
  final List<RegExp> nameRules;

  factory AdBlockRules.fromJson(Map<String, dynamic> j) {
    final enabled = j['enabled'] is bool ? j['enabled'] as bool : true;
    final urls = _parseList(j['urlRules'] ?? j['adUrl']);
    final names = _parseList(j['nameRules'] ?? j['adName']);
    return AdBlockRules(enabled: enabled, urlRules: urls, nameRules: names);
  }

  /// 解析文本；坏 JSON 返回 null（调用方提示导入失败）。
  static AdBlockRules? tryParse(String text) {
    try {
      final j = jsonDecode(text);
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
