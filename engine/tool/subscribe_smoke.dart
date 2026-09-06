// 订阅仓库导入冒烟：对真实社区仓库跑一次 RepoClient.subscribe。
// 用法：dart run tool/subscribe_smoke.dart [repo]
import 'dart:io';

import 'package:engine/engine.dart';

Future<void> main(List<String> args) async {
  final repo = args.isNotEmpty ? args[0] : 'https://github.com/AcgLibrary/ppcat_store';
  print('订阅 $repo …');
  final bundle = await RepoClient(fetcher: HttpFetcher()).subscribe(repo);
  print('Track ${bundle.track}: 导入 ${bundle.sources.length} 个源');
  final withSearch =
      bundle.sources.where((s) => s.rules.searchUrl.isNotEmpty).length;
  print('其中 searchUrl 非空: $withSearch');
  if (bundle.sources.isNotEmpty) {
    final s = bundle.sources.first;
    print('样例: ${s.name}  ${s.url}  search=${s.rules.searchUrl}');
  }
  exit(bundle.sources.isNotEmpty && withSearch > 0 ? 0 : 1);
}
