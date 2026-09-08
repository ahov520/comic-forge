import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_bytes.dart';

/// 阅读器 [CachedNetworkImage] 使用的磁盘缓存。与离线下载目录相互独立。
class ImageCacheStore {
  ImageCacheStore({
    BaseCacheManager? manager,
    Future<Directory> Function()? directory,
  }) : _manager = manager, // ignore: prefer_initializing_formals
       _directory = directory ?? _defaultDirectory;

  final BaseCacheManager? _manager;
  final Future<Directory> Function() _directory;

  BaseCacheManager get manager =>
      _manager ?? CachedNetworkImageProvider.defaultCacheManager;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getTemporaryDirectory()).path}/${DefaultCacheManager.key}',
  );

  Future<int?> usageBytes() async {
    try {
      return await directorySize(await _directory());
    } catch (_) {
      return null;
    }
  }

  Future<void> evictUrls(Iterable<String> urls) async {
    final memory = PaintingBinding.instance.imageCache;
    for (final url in urls) {
      if (url.isEmpty) continue;
      try {
        await manager.removeFile(url);
      } catch (_) {}
      memory.evict(CachedNetworkImageProvider(url));
    }
  }

  Future<void> clearAll() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      await manager.emptyCache();
    } catch (_) {}
  }
}
