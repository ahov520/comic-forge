import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/comic_source.dart';
import 'ppcat_store.dart';

/// 皮皮喵「本地备份」(.pbak) 解析器。
///
/// 备份格式（2026-09 用真实样本逆向确认）：
/// ```
/// .pbak = gzip( JSON )
/// JSON = {
///   "time": ms, "version": 260201,
///   "favs": [], "downs": [], "tags": [],
///   "rules": [ {"name": 源名, "url": "ppcat://ruleLink?data=<base64>"} ],
///   "prefs": { "storeIndex": 1, "gitRuleMap": "{\"url\":\"...\",\"auto\":true}" }
/// }
/// ```
/// ruleLink 的 data = `.mh_rules` 加密 ZIP（见 [PpcatStoreInspector]）：
/// `[加密区][明文CDH][EOCD][LFH尾片段+明文deflate数据]`。
/// 明文分片可解出源 JSON 的前缀；全量需注入解密器（待密钥取证）。
class PipimiaoBackup {
  PipimiaoBackup({
    required this.timeMs,
    required this.version,
    required this.sharedRules,
    required this.storeSubscriptions,
  });

  final int timeMs;
  final int version;

  /// 备份里的分享源（ruleLink）。
  final List<SharedRule> sharedRules;

  /// 已订阅的源仓库（gitRuleMap）。
  final List<({String url, bool auto})> storeSubscriptions;

  static PipimiaoBackup parse(List<int> pbakBytes) {
    final jsonBytes = GZipDecoder().decodeBytes(pbakBytes);
    final j = jsonDecode(utf8.decode(jsonBytes, allowMalformed: true)) as Map<String, dynamic>;
    final rules = <SharedRule>[];
    for (final r in (j['rules'] as List? ?? [])) {
      if (r is! Map<String, dynamic>) continue;
      final url = (r['url'] ?? '') as String;
      const marker = 'ppcat://ruleLink?data=';
      if (!url.startsWith(marker)) continue;
      final b64 = url.substring(marker.length);
      rules.add(SharedRule(
        name: (r['name'] ?? '') as String,
        storeBytes: base64Decode(b64 + '=' * (-b64.length % 4)),
      ));
    }
    final subs = <({String url, bool auto})>[];
    final grpc = j['prefs']?['gitRuleMap'];
    if (grpc is String && grpc.isNotEmpty) {
      try {
        final g = jsonDecode(grpc);
        if (g is Map && g['url'] is String) {
          subs.add((url: g['url'] as String, auto: g['auto'] == true));
        } else if (g is Map) {
          g.forEach((k, v) {
            if (v is Map && v['url'] is String) {
              subs.add((url: v['url'] as String, auto: v['auto'] == true));
            }
          });
        }
      } on FormatException {
        // 忽略损坏的订阅信息
      }
    }
    return PipimiaoBackup(
      timeMs: (j['time'] is int) ? j['time'] as int : 0,
      version: (j['version'] is int) ? j['version'] as int : 0,
      sharedRules: rules,
      storeSubscriptions: subs,
    );
  }

  static PipimiaoBackup parseFile(String path) => parse(File(path).readAsBytesSync());

  /// 从全部分享源的明文分片里提取完整源条目（容错跳过被截断的尾部）。
  List<ComicSource> extractCompleteSources() {
    final out = <ComicSource>[];
    for (final r in sharedRules) {
      final partial = r.partialRulesJson();
      if (partial == null) continue;
      out.addAll(_parseTruncatedArray(partial));
    }
    return out;
  }

  /// 解析可能被截断的 `[{"..."},{...` 源数组：按括号配对逐条解码，
  /// 损坏/不完整条目跳过。
  static List<ComicSource> _parseTruncatedArray(String s) {
    final out = <ComicSource>[];
    var i = s.indexOf('{');
    while (i >= 0 && i < s.length) {
      final end = _matchObject(s, i);
      if (end < 0) break; // 尾部不完整
      try {
        final obj = jsonDecode(s.substring(i, end + 1));
        if (obj is Map<String, dynamic> &&
            ((obj['bookSourceName'] ?? obj['sourceName'] ?? '') as String).isNotEmpty) {
          out.add(ComicSource.fromPpcatFlat(obj));
        }
        i = end + 1;
      } on FormatException {
        i = s.indexOf('{', i + 1);
      }
    }
    return out;
  }

  /// 返回与 s[start] '{' 配对的 '}' 下标；未闭合返回 -1。
  static int _matchObject(String s, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (esc) {
        esc = false;
        continue;
      }
      if (c == 0x5C /* 反斜杠 */) {
        if (inStr) esc = true;
        continue;
      }
      if (c == 0x22 /* 引号 */) {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (c == 0x7B /* 左花括号 */) depth++;
      if (c == 0x7D /* 右花括号 */) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}

/// 一条分享源（加密 .mh_rules 包 + 已解出的明文部分）。
class SharedRule {
  SharedRule({required this.name, required this.storeBytes});

  final String name;
  final List<int> storeBytes;

  /// 结构信息（entry 名/crc/尺寸）。
  PpcatStoreStructure? inspect() {
    try {
      return PpcatStoreInspector.inspect(storeBytes);
    } on FormatException {
      return null;
    }
  }

  /// 尾部明文 deflate 分片解出的源 JSON 前缀（可能截断）。
  String? partialRulesJson() => PpcatStoreInspector.partialJson(storeBytes);
}