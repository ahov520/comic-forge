import 'dart:convert';

import 'package:http/http.dart' as http;

import 'domain_blocklist.dart';
import 'request.dart';

/// 抓取抽象：引擎不绑定具体 HTTP 栈，应用层可注入带 UA/Cookie/代理的实现。
abstract class Fetcher {
  /// 返回解码后的文本。
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? charset,
  });

  /// 返回原始字节。
  Future<List<int>> getBytes(String url, {Map<String, String>? headers});

  /// 发送完整请求（支持 POST form/JSON 与附加请求头）。
  Future<List<int>> send(SourceRequest request, {Map<String, String>? headers});
}

/// 在委托前按 [NetworkPolicy] 拦截主机；供测试包装 FakeFetcher，生产路径也可叠一层。
class PolicyFetcher implements Fetcher {
  PolicyFetcher({required this.inner, required this.policy});

  final Fetcher inner;
  final NetworkPolicy policy;

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? charset,
  }) async {
    policy.assertAllowed(url);
    return inner.getString(url, headers: headers, charset: charset);
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    policy.assertAllowed(url);
    return inner.getBytes(url, headers: headers);
  }

  @override
  Future<List<int>> send(
    SourceRequest request, {
    Map<String, String>? headers,
  }) async {
    policy.assertAllowed(request.url);
    return inner.send(request, headers: headers);
  }
}

/// 默认实现：直接 http.get/post；挂上 [policy] 后会逐跳检查重定向主机。
class HttpFetcher implements Fetcher {
  HttpFetcher({
    http.Client? client,
    this.defaultHeaders,
    this.policy,
    this.maxRedirects = 5,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String>? defaultHeaders;
  NetworkPolicy? policy;
  final int maxRedirects;

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? charset,
  }) async {
    final bytes = await getBytes(url, headers: headers);
    return _decode(bytes, charset);
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    final h = {...?defaultHeaders, ...?headers};
    if (policy != null) {
      return _exchange(method: 'GET', url: url, headers: h);
    }
    final res = await _client.get(Uri.parse(url), headers: h);
    if (res.statusCode >= 400) {
      throw FetchException('HTTP ${res.statusCode} for $url');
    }
    return res.bodyBytes;
  }

  @override
  Future<List<int>> send(
    SourceRequest request, {
    Map<String, String>? headers,
  }) async {
    final h = {...?defaultHeaders, ...request.headers, ...?headers};
    if (policy != null) {
      return _exchange(
        method: request.isPost ? 'POST' : 'GET',
        url: request.url,
        headers: h,
        body: request.isPost ? request.body : null,
      );
    }
    final uri = Uri.parse(request.url);
    final res = request.isPost
        ? await _client.post(uri, headers: h, body: request.body)
        : await _client.get(uri, headers: h);
    if (res.statusCode >= 400) {
      throw FetchException('HTTP ${res.statusCode} for ${request.url}');
    }
    return res.bodyBytes;
  }

  /// 关闭自动跟随，逐跳解析 Location 并套用黑名单（含相对 / 协议相对地址）。
  Future<List<int>> _exchange({
    required String method,
    required String url,
    required Map<String, String> headers,
    String? body,
  }) async {
    var currentMethod = method.toUpperCase();
    var currentUri = Uri.parse(url);
    var currentBody = body;
    final seen = <String>{};

    for (var hop = 0; hop <= maxRedirects; hop++) {
      policy?.assertAllowed(currentUri.toString());
      final stamp = '$currentMethod ${currentUri.toString()}';
      if (!seen.add(stamp)) {
        throw FetchException('Redirect loop for $url');
      }

      final req = http.Request(currentMethod, currentUri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(headers);
      if (currentBody != null) req.body = currentBody;

      final streamed = await _client.send(req);
      if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
        final location = streamed.headers['location'];
        await streamed.stream.drain<void>();
        if (location == null || location.trim().isEmpty) {
          throw FetchException('HTTP ${streamed.statusCode} for $currentUri');
        }
        final next = currentUri.resolve(location);
        if (streamed.statusCode == 303 ||
            (currentMethod == 'POST' &&
                (streamed.statusCode == 301 || streamed.statusCode == 302))) {
          currentMethod = 'GET';
          currentBody = null;
        }
        currentUri = next;
        continue;
      }

      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 400) {
        throw FetchException('HTTP ${res.statusCode} for $currentUri');
      }
      return res.bodyBytes;
    }
    throw FetchException('Too many redirects for $url');
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
