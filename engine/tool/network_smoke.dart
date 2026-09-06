// 真实网络冒烟：从内置源快照挑样例源逐个搜索，验证 P0 修复后源真正可用。
// 用法：dart run tool/network_smoke.dart [关键词] [样本数]
// 安全守则（Mimosa 约束）：仅 http/https；校验 host，拒绝环回/私有/保留地址。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';

/// 仅放行 http/https 且 host 为公网域名的 URL。
bool isPublicHttpUrl(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null) return false;
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  final host = u.host;
  if (host.isEmpty || !host.contains('.')) return false;
  if (host == 'localhost' || host.endsWith('.localhost')) return false;
  if (host.endsWith('.local') || host.endsWith('.internal')) return false;
  // 环回/私有/保留 IPv4（点分十进制字面量）
  final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (ip != null) {
    final o = [1, 2, 3, 4].map((i) => int.parse(ip.group(i)!)).toList();
    if (o.any((x) => x > 255)) return false;
    if (o[0] == 0 || o[0] == 10 || o[0] == 127) return false;
    if (o[0] == 169 && o[1] == 254) return false;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return false;
    if (o[0] == 192 && o[1] == 168) return false;
    if (o[0] >= 224) return false;
    return true;
  }
  // IPv6 字面量一律拒绝（冒烟只打公网点分域名）
  if (host.contains(':')) return false;
  return true;
}

Future<void> main(List<String> args) async {
  final keyword = args.isNotEmpty ? args[0] : '一人之下';
  final sampleN = args.length > 1 ? int.parse(args[1]) : 12;
  final nameFilter = args.length > 2 ? args[2] : null;

  final j = jsonDecode(File('../app/assets/store.json').readAsStringSync())
      as Map<String, dynamic>;
  final sources = (j['sources'] as List)
      .whereType<Map<String, dynamic>>()
      .map(ComicSource.fromPpcatFlat)
      .where((s) => s.rules.searchUrl.isNotEmpty)
      .where((s) => nameFilter == null || s.name.contains(nameFilter))
      .toList();

  // 样本挑选：带 headers（常见反爬 UA）的优先，域名分散（每个根域只取 1 条）
  final seenDomain = <String>{};
  final sample = <ComicSource>[];
  for (final s in sources) {
    final host = Uri.tryParse(s.url)?.host ?? '';
    if (!isPublicHttpUrl(s.url)) continue;
    final root = host.split('.').length <= 2 ? host : host.split('.').sublist(1).join('.');
    if (!seenDomain.add(root)) continue;
    sample.add(s);
    if (sample.length >= sampleN * 3) break;
  }
  sample.sort((a, b) {
    final ah = a.headers.isNotEmpty ? 0 : 1;
    final bh = b.headers.isNotEmpty ? 0 : 1;
    return ah.compareTo(bh);
  });

  final fetcher = HttpFetcher();
  var ok = 0, empty = 0, failed = 0;
  for (final s in sample.take(sampleN)) {
    final rt = SourceRuntime(source: s, fetcher: fetcher);
    try {
      final paged = await rt.search(keyword).timeout(const Duration(seconds: 15));
      final url = Uri.parse(s.url).resolve(renderUrlTemplate(
          s.rules.searchUrl,
          {'key': keyword, 'searchKey': keyword, 'searchPage': '1', 'page': '1'}));
      if (paged.items.isNotEmpty) {
        ok++;
        final first = paged.items.first;
        print('✅ ${s.name}  结果=${paged.items.length}  首条=${first.name}  $url');
      } else {
        empty++;
        print('⚪ ${s.name}  0 条（可能关键词不匹配或列表规则需调）  $url');
      }
    } catch (e) {
      failed++;
      final msg = e.toString().split('\n').first;
      print('❌ ${s.name}  $msg');
    }
  }
  print('---');
  print('样本=$sampleN  有结果=$ok  空结果=$empty  失败=$failed  关键词=$keyword');
  exit(ok > 0 ? 0 : 1);
}
