import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

String downloadKey(Iterable<String> parts) =>
    sha256.convert(utf8.encode(jsonEncode(parts.toList()))).toString();

/// 离线文件放在应用数据目录，不受网络图片缓存的过期和容量淘汰影响。
class DownloadStore {
  DownloadStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;
  Future<Directory>? _root;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/comic-forge/downloads',
  );

  Future<Directory> _rootDirectory() => _root ??= () async {
    try {
      return await (await _directory()).create(recursive: true);
    } catch (_) {
      _root = null;
      rethrow;
    }
  }();

  Future<File> _file(String taskId, String url) async {
    final root = await _rootDirectory();
    return File(
      '${root.path}/${downloadKey([taskId])}/${downloadKey([url])}.img',
    );
  }

  Future<bool> contains(String taskId, String url) async {
    final file = await _file(taskId, url);
    return await file.exists() && await file.length() > 0;
  }

  Future<String> imageUri(String taskId, String url) async =>
      (await _file(taskId, url)).uri.toString();

  Future<void> write(String taskId, String url, List<int> bytes) async {
    final file = await _file(taskId, url);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  }

  Future<void> remove(String taskId) async {
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/${downloadKey([taskId])}');
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
