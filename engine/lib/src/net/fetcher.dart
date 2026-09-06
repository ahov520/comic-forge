import 'dart:convert';

import 'package:http/http.dart' as http;

/// 抓取抽象：引擎不绑定具体 HTTP 栈，应用层可注入带 UA/Cookie/代理的实现。
abstract class Fetcher {
  /// 返回解码后的文本。
  Future<String> getString(String url, {Map<String, String>? headers, String charset});

  /// 返回原始字节。
  Future<List<int>> getBytes(String url, {Map<String, String>? headers});
}

/// 默认实现：直接 http.get。
class HttpFetcher implements Fetcher {
  HttpFetcher({http.Client? client, this.defaultHeaders})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String>? defaultHeaders;

  @override
  Future<String> getString(String url, {Map<String, String>? headers, String? charset}) async {
    final bytes = await getBytes(url, headers: headers);
    return _decode(bytes, charset);
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    final res = await _client.get(
      Uri.parse(url),
      headers: {...?defaultHeaders, ...?headers},
    );
    if (res.statusCode >= 400) {
      throw FetchException('HTTP ${res.statusCode} for $url');
    }
    return res.bodyBytes;
  }

  static String _decode(List<int> bytes, String? charset) {
    if (charset != null && charset.isNotEmpty) {
      final cs = Encoding.getByName(charset.toLowerCase());
      if (cs != null) return cs.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class FetchException implements Exception {
  FetchException(this.message);
  final String message;

  @override
  String toString() => 'FetchException: $message';
}
