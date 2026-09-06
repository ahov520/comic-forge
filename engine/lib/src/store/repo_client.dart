import 'dart:convert';

import '../models/comic_source.dart';
import '../net/fetcher.dart';
import 'ppcat_store.dart';

/// 源仓库引用：host 为 github / gitee。
class RepoRef {
  RepoRef({required this.host, required this.user, required this.repo, this.branch = 'master'});

  final String host;
  final String user;
  final String repo;
  final String branch;

  /// 解析用户输入：完整 URL / `user/repo` 简写。
  /// 兼容 ppcat 的正则语义：`(gitee|github).com/user/repo`。
  static RepoRef? parse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http')) {
      s = 'https://github.com/$s';
    }
    final m = RegExp(r'https?://(?:www\.)?(gitee|github)\.com/([\w.\-]+)/([\w.\-]+)').firstMatch(s);
    if (m == null) return null;
    return RepoRef(host: m.group(1)!, user: m.group(2)!, repo: m.group(3)!);
  }

  /// 一个仓库的多个 raw 候选地址（按优先级）。
  List<String> rawCandidates(String file) {
    switch (host) {
      case 'github':
        return [
          'https://raw.githubusercontent.com/$user/$repo/$branch/$file',
          'https://cdn.jsdelivr.net/gh/$user/$repo@$branch/$file',
          'https://raw.githubusercontent.com/$user/$repo/main/$file',
          'https://cdn.jsdelivr.net/gh/$user/$repo@main/$file',
        ];
      case 'gitee':
        return [
          'https://gitee.com/$user/$repo/raw/$branch/$file',
          'https://gitee.com/$user/$repo/raw/main/$file',
        ];
      default:
        return [];
    }
  }

  String get canonical => '$host.com/$user/$repo';
}

/// 仓库 meta（键名与 ppcat 保持一致）。
class StoreMeta {
  StoreMeta({
    this.ruleId = '0',
    this.ruleVersion = 0,
    this.ruleContent = '',
    this.ruleAuto = true,
  });

  final String ruleId;
  final int ruleVersion;
  final String ruleContent;
  final bool ruleAuto;

  factory StoreMeta.fromJson(Map<String, dynamic> j) => StoreMeta(
        ruleId: (j['ruleId'] ?? '0') as String,
        ruleVersion: (j['ruleVersion'] is int)
            ? j['ruleVersion'] as int
            : int.tryParse('${j['ruleVersion']}') ?? 0,
        ruleContent: (j['ruleContent'] ?? '') as String,
        ruleAuto: (j['ruleAuto'] ?? true) as bool,
      );

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'ruleVersion': ruleVersion,
        'ruleContent': ruleContent,
        'ruleAuto': ruleAuto,
      };
}

/// 拉取结果：meta + 源列表。
class StoreBundle {
  StoreBundle({required this.ref, required this.meta, required this.sources, this.track});

  final RepoRef ref;
  final StoreMeta meta;
  final List<ComicSource> sources;

  /// 'A' = 明文 JSON；'B' = ppcat 加密 .mh_rules。
  final String? track;
}

/// 仓库订阅客户端。
class RepoClient {
  RepoClient({required this.fetcher, this.storeDecryptor});

  final Fetcher fetcher;

  /// Track B：ppcat 加密 store 解密器（Phase 0 取证后注入；null 时跳过加密仓库）。
  final StoreDecryptor? storeDecryptor;

  /// 订阅仓库：自动识别明文（Track A）与加密（Track B）。
  Future<StoreBundle> subscribe(String repoInput) async {
    final ref = RepoRef.parse(repoInput);
    if (ref == null) {
      throw const FormatException('无法识别的仓库地址（支持 github.com/user/repo 或 gitee.com/user/repo）');
    }
    final meta = await _fetchMeta(ref);
    final sources = await _fetchStore(ref, meta);
    return StoreBundle(ref: ref, meta: meta, sources: sources, track: _lastTrack);
  }

  String? _lastTrack;

  Future<StoreMeta> _fetchMeta(RepoRef ref) async {
    // Track A 优先 meta.json（明文仓库约定），回落 ppcat 的 meta。
    for (final name in const ['meta.json', 'meta']) {
      for (final url in ref.rawCandidates(name)) {
        try {
          final text = await fetcher.getString(url);
          return StoreMeta.fromJson(jsonDecode(text) as Map<String, dynamic>);
        } on Exception {
          // 换下一个候选
        }
      }
    }
    return StoreMeta(); // 仓库没有 meta 时视为版本 0
  }

  Future<List<ComicSource>> _fetchStore(RepoRef ref, StoreMeta meta) async {
    // Track A：store.json 明文
    for (final url in ref.rawCandidates('store.json')) {
      try {
        final text = await fetcher.getString(url);
        final sources = _parsePlainStore(text);
        if (sources != null) {
          _lastTrack = 'A';
          return sources;
        }
      } on Exception {
        // 试下一个候选
      }
    }
    // Track B：ppcat 加密 store（二进制）
    if (storeDecryptor != null) {
      for (final url in ref.rawCandidates('store')) {
        try {
          final bytes = await fetcher.getBytes(url);
          final sources = _parsePpcatStore(bytes);
          if (sources != null) {
            _lastTrack = 'B';
            return sources;
          }
        } on Exception {
          // 试下一个候选
        }
      }
    }
    throw FetchException('仓库 ${ref.canonical} 未找到可识别的 store（需要明文 store.json 或注入加密解码器）');
  }

  /// 明文 store.json → 源列表。结构宽松：顶层数组、{sources:[...]}、
  /// {data:[...]} 都认；源条目兼容嵌套与 ppcat 平铺两种形态。
  List<ComicSource>? _parsePlainStore(String text) {
    try {
      final j = jsonDecode(text);
      List<dynamic>? list;
      if (j is List) {
        list = j;
      } else if (j is Map) {
        list = (j['sources'] ?? j['data']) as List<dynamic>?;
      }
      if (list == null) return null;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => _looksPpcatFlat(m) ? ComicSource.fromPpcatFlat(m) : ComicSource.fromJson(m))
          .toList();
    } on FormatException {
      return null;
    }
  }

  static bool _looksPpcatFlat(Map<String, dynamic> m) =>
      m.containsKey('ruleSearchList') || m.containsKey('ruleFindList') || m.containsKey('ruleId');

  /// ppcat 加密 store → 源列表（需要注入解密器）。
  List<ComicSource>? _parsePpcatStore(List<int> bytes) {
    try {
      final structure = PpcatStoreInspector.inspect(bytes);
      final plainZip = PpcatStoreInspector.decrypt(structure, storeDecryptor!);
      final jsonText = PpcatStoreInspector.unzipFirstEntryText(plainZip);
      final j = jsonDecode(jsonText);
      List<dynamic>? list;
      if (j is List) {
        list = j;
      } else if (j is Map) {
        list = (j['sources'] ?? j['data'] ?? j['rules']) as List<dynamic>?;
        // .mh_rules 可能是 {来源名: 源对象} 的 map
        if (list == null && j is Map<String, dynamic>) {
          return j.values
              .whereType<Map<String, dynamic>>()
              .map(ComicSource.fromPpcatFlat)
              .toList();
        }
      }
      if (list == null) return null;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => _looksPpcatFlat(m) ? ComicSource.fromPpcatFlat(m) : ComicSource.fromJson(m))
          .toList();
    } on Exception {
      return null;
    }
  }
}
