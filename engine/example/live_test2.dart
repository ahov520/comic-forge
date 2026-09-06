import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';

Future<void> main() async {
  final storeJson = jsonDecode(File(r'C:\Users\ahov\comic-forge\store-snapshot\store.json').readAsStringSync());
  final sources = (storeJson['sources'] as List)
      .map((e) => ComicSource.fromPpcatFlat((e as Map).cast<String, dynamic>()))
      .toList();
  final fetcher = HttpFetcher(defaultHeaders: {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
  });
  final targets = ['isamanhua', 'mkzhan', 'buka', 'kuaikan', 'u17'];
  for (final t in targets) {
    final src = sources.where((s) => s.url.contains(t)).firstOrNull;
    if (src == null) continue;
    final rt = SourceRuntime(source: src, fetcher: fetcher);
    final entries = rt.exploreEntries();
    if (entries.isEmpty) { print('${src.name}: 无发现入口'); continue; }
    try {
      final page = await rt.explore(entries.first.$2).timeout(const Duration(seconds: 15));
      var out = '${src.name}: ${page.items.length}本';
      if (page.items.isNotEmpty) {
        final b = page.items.first;
        try {
          final (_, chs) = await rt.detail(b.bookUrl).timeout(const Duration(seconds: 15));
          out += ' | 详情「${b.name}」章节${chs.length}';
          if (chs.isNotEmpty) {
            final imgs = await rt.images(chs.first.url).timeout(const Duration(seconds: 15));
            out += ' | 图${imgs.length}';
          }
        } catch (e) {
          out += ' | 详情失败:$e';
        }
      }
      print(out);
    } catch (e) {
      print('${src.name}: 探索失败 $e');
    }
  }
}
