import 'dart:convert';

import 'package:http/http.dart' as http;

/// 最小 WebDAV 客户端：MKCOL（逐级建目录）/ PUT / GET + Basic 认证。
/// 备份/恢复场景够用；目录已存在（405）视为成功。
class WebDavClient {
  WebDavClient({
    required String baseUrl,
    this.username = '',
    this.password = '',
    http.Client? client,
  })  : _base = _normalizeBase(baseUrl),
        _client = client ?? http.Client();

  final String _base;
  final String username;
  final String password;
  final http.Client _client;

  static String _normalizeBase(String url) {
    var b = url.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      throw const FormatException('WebDAV 地址须为 http/https');
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// 路径 → URI：拒绝 `..` 穿越；多斜杠归一。
  Uri _uri(String path) {
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.any((s) => s == '..')) {
      throw const FormatException('路径不允许包含 ..');
    }
    return Uri.parse('$_base/${segments.join('/')}');
  }

  Map<String, String> get _auth {
    if (username.isEmpty && password.isEmpty) return const {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}'
    };
  }

  /// 逐级创建目录；405（已存在）视为成功。
  Future<void> mkdirp(String dirPath) async {
    final segments =
        dirPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..')) {
      throw const FormatException('路径不允许包含 ..');
    }
    var prefix = '';
    for (final seg in segments) {
      prefix = '$prefix/$seg';
      final res = await _client.send(http.Request('MKCOL', _uri(prefix))
        ..headers.addAll(_auth));
      // drain 流避免连接泄漏
      await res.stream.drain<void>();
      if (res.statusCode >= 400 && res.statusCode != 405) {
        throw WebDavException('MKCOL $prefix 失败：HTTP ${res.statusCode}');
      }
    }
  }

  /// 上传文件（父目录需已存在或先 mkdirp）。
  Future<void> putBytes(String path, List<int> bytes) async {
    final res = await _client.send(http.Request('PUT', _uri(path))
      ..headers.addAll(_auth)
      ..bodyBytes = bytes);
    await res.stream.drain<void>();
    if (res.statusCode >= 400) {
      throw WebDavException('PUT $path 失败：HTTP ${res.statusCode}');
    }
  }

  /// 下载文件；404 抛 [WebDavException.notFound]。
  Future<List<int>> getBytes(String path) async {
    final res = await _client.get(_uri(path), headers: _auth);
    if (res.statusCode == 404) throw WebDavException.notFound(path);
    if (res.statusCode >= 400) {
      throw WebDavException('GET $path 失败：HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }
}

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;

  factory WebDavException.notFound(String path) =>
      WebDavException('远端不存在：$path');

  @override
  String toString() => 'WebDavException: $message';
}
