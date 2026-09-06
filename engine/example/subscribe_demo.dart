// 真实网络冒烟：订阅 AcgLibrary/ppcat_store + H-Viewer-Sites 转换。
// 运行：dart run example/subscribe_demo.dart
import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:engine/src/adapter/hviewer_adapter.dart';

Future<void> main() async {
  final fetcher = HttpFetcher(defaultHeaders: {'User-Agent': 'Mozilla/5.0'});
  final repo = RepoClient(fetcher: fetcher); // 不注入解密器 → Track B 应明确报错

  print('=== 1) 订阅 AcgLibrary/ppcat_store（预期：识别为加密 Track B，无解码器则报错）===');
  try {
    final b = await repo.subscribe('https://github.com/AcgLibrary/ppcat_store');
    print('  Track ${b.track}: ${b.sources.length} 个源, ruleVersion=${b.meta.ruleVersion}');
  } catch (e) {
    print('  预期内失败: ${e.toString().substring(0, e.toString().length.clamp(0, 120))}');
  }

  print('=== 2) H-Viewer-Sites 索引 → 转换一个站点规则 ===');
  try {
    final idx = await fetcher.getString(
        'https://cdn.jsdelivr.net/gh/ghostgzt/H-Viewer-Sites@master/Index/sites.json');
    final groups = (jsonDecode(idx) as List).cast<Map<String, dynamic>>();
    final firstSite = groups.first['sites'].first as Map<String, dynamic>;
    print('  选取站点: ${firstSite['title']}  规则: ${firstSite['json']}');
    final ruleText = await fetcher.getString(
        (firstSite['json'] as String).replaceFirst(
            'https://raw.githubusercontent.com/H-Viewer-Sites/Index/master/',
            'https://cdn.jsdelivr.net/gh/ghostgzt/H-Viewer-Sites@master/Index/'));
    final src = HViewerAdapter.convert((jsonDecode(ruleText) as Map).cast<String, dynamic>());
    print('  转换成功: ${src.name} | 发现入口=${src.rules.exploreUrl.split('\n').length}组 | 列表规则=${src.rules.findList}');
  } catch (e) {
    print('  H-Viewer 样例失败(网络/站点已死可容忍): $e');
  }
}
