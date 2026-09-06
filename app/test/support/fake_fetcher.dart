import 'dart:async';
import 'dart:convert';

import 'package:engine/engine.dart';

/// 可控制响应时机的内存抓取器，测试不访问网络。
class FakeFetcher implements Fetcher {
  FakeFetcher(this.respond);

  final FutureOr<String> Function(Uri uri) respond;
  final List<Uri> requests = [];

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? charset,
  }) async {
    final uri = Uri.parse(url);
    requests.add(uri);
    return respond(uri);
  }

  @override
  Future<List<int>> getBytes(
    String url, {
    Map<String, String>? headers,
  }) async => utf8.encode(await getString(url, headers: headers));

  @override
  Future<List<int>> send(
    SourceRequest request, {
    Map<String, String>? headers,
  }) => getBytes(request.url, headers: {...request.headers, ...?headers});
}
