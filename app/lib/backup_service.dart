import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;

import 'state/app_state.dart';

/// 备份/恢复载荷（书架 + 源库 + 阅读进度 + 订阅仓库）。
class BackupService {
  BackupService._();

  static const formatVersion = 1;
  static const defaultRemotePath = '/comic-forge/backup.json';

  /// 从 AppState 导出 JSON 文本。
  static String exportJson(AppState st) {
    return jsonEncode({
      'app': 'comic-forge',
      'version': formatVersion,
      'at': DateTime.now().millisecondsSinceEpoch,
      'sources': st.sources.map((s) => s.toJson()).toList(),
      'shelf': st.shelf.map((b) => b.toJson()).toList(),
      'progress': st.progress.map((k, v) => MapEntry(k, v.toJson())),
      'repos': st.repos,
    });
  }

  /// 解析备份 JSON；坏格式返回 null。
  static Map<String, dynamic>? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map<String, dynamic> && j['app'] == 'comic-forge') return j;
    } on FormatException {
      return null;
    }
    return null;
  }

  /// 合并导入到 AppState；返回各类新增数量。
  static Future<({int sources, int shelf, int progress, int repos})> importJson(
      AppState st, String text) async {
    final j = tryParse(text);
    if (j == null) {
      throw const FormatException('备份文件格式不正确（需要 comic-forge 导出的 JSON）');
    }
    final sources = (j['sources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromJson)
        .toList();
    final shelf = (j['shelf'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Book.fromJson)
        .toList();
    final progress = (j['progress'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(
            k, ReadingProgress.fromJson(v as Map<String, dynamic>)));
    final repos = (j['repos'] as List? ?? []).cast<String>();
    return st.mergeBackup(
        sources: sources, shelf: shelf, progress: progress, repos: repos);
  }

  /// 备份到 WebDAV：先逐级建目录再上传。[client] 可注入（测试用）。
  static Future<void> backupToWebDav({
    required AppState st,
    required String baseUrl,
    String username = '',
    String password = '',
    String remotePath = defaultRemotePath,
    http.Client? client,
  }) async {
    final dav = WebDavClient(
        baseUrl: baseUrl, username: username, password: password, client: client);
    final dir = remotePath.substring(0, remotePath.lastIndexOf('/'));
    if (dir.isNotEmpty) await dav.mkdirp(dir);
    await dav.putBytes(remotePath, utf8.encode(exportJson(st)));
  }

  /// 从 WebDAV 恢复（合并语义）。返回各类新增数量。
  static Future<({int sources, int shelf, int progress, int repos})>
      restoreFromWebDav({
    required AppState st,
    required String baseUrl,
    String username = '',
    String password = '',
    String remotePath = defaultRemotePath,
    http.Client? client,
  }) async {
    final dav = WebDavClient(
        baseUrl: baseUrl, username: username, password: password, client: client);
    final text = utf8.decode(await dav.getBytes(remotePath));
    return importJson(st, text);
  }
}
