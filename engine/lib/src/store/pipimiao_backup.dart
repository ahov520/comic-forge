import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

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
  String? partialRulesJson() {
    final raw = storeBytes;
    final sig = [0x50, 0x4b, 0x05, 0x06]; // PK\x05\x06
    var eocd = -1;
    for (var i = raw.length - 22; i >= 0; i--) {
      if (raw[i] == sig[0] && raw[i + 1] == sig[1] && raw[i + 2] == sig[2] && raw[i + 3] == sig[3]) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;
    final codec = ZLibCodec(raw: true);
    for (var start = eocd + 22; start < raw.length - 2; start++) {
      try {
        final out = codec.decoder.convert(raw.sublist(start));
        final s = utf8.decode(out, allowMalformed: true);
        if (s.contains('bookSource') || s.contains('ruleSearch')) return s;
      } on Exception {
        // 换下一个偏移
      }
    }
    return null;
  }
}
