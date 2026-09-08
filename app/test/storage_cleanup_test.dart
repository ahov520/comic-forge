import 'dart:io';

import 'package:comic_forge/services/image_cache_store.dart';
import 'package:comic_forge/services/storage_bytes.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCacheManager extends Fake implements BaseCacheManager {
  _FakeCacheManager({this.onEmpty});

  final Future<void> Function()? onEmpty;
  var emptied = 0;
  final removed = <String>[];

  @override
  Future<void> emptyCache() async {
    emptied++;
    await onEmpty?.call();
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('占用文案区分已知大小与估算失败', () {
    expect(formatStorageBytes(512), '512 B');
    expect(formatStorageBytes(1536), '1.5 KB');
    expect(formatStorageBytes(2 * 1024 * 1024), '2.0 MB');
    expect(
      storageUsageLabel(downloads: 512, cache: 1536),
      '离线约 512 B · 图片缓存约 1.5 KB',
    );
    expect(
      storageUsageLabel(downloads: null, cache: null),
      '离线暂无法估算 · 图片缓存暂无法估算',
    );
  });

  test('图片缓存可估算目录占用、按 URL 清除，并在清空时不影响注入的目录以外的文件', () async {
    final dir = await Directory.systemTemp.createTemp(
      'comic-forge-cache-size-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await File('${dir.path}/a.bin').writeAsBytes(List.filled(80, 1));
    await File('${dir.path}/nested/b.bin').create(recursive: true);
    await File('${dir.path}/nested/b.bin').writeAsBytes(List.filled(20, 2));
    final outside = File('${dir.path}-keep.bin');
    await outside.writeAsBytes(List.filled(40, 3));
    addTearDown(() async {
      if (await outside.exists()) await outside.delete();
    });
    final manager = _FakeCacheManager(
      onEmpty: () async {
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create();
      },
    );
    final store = ImageCacheStore(manager: manager, directory: () async => dir);
    expect(await store.usageBytes(), 100);
    await store.evictUrls(['https://cache.example/page.png', '']);
    expect(manager.removed, ['https://cache.example/page.png']);
    await store.clearAll();
    expect(manager.emptied, 1);
    expect(await store.usageBytes(), 0);
    expect(await outside.exists(), isTrue);
  });
}
