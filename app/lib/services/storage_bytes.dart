import 'dart:io';

import 'package:flutter/foundation.dart';

/// Android 上提供占用估算与清理入口；其它平台隐藏，避免误清桌面测试数据。
bool get supportsStorageCleanup =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String storageUsageLabel({int? downloads, int? cache}) {
  String part(String name, int? bytes) =>
      bytes == null ? '$name暂无法估算' : '$name约 ${formatStorageBytes(bytes)}';
  return '${part('离线', downloads)} · ${part('图片缓存', cache)}';
}

Future<int> directorySize(Directory directory) async {
  if (!await directory.exists()) return 0;
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {}
    }
  }
  return total;
}
