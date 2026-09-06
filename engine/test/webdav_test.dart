import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Client _mock(
    Future<http.Response> Function(http.Request req) handler,
    {List<(String, String)>? log}) {
  return MockClient.streaming((req, bodyStream) async {
    final body = await utf8.decoder.bind(bodyStream).join();
    final r = http.Request(req.method, req.url)
      ..headers.addAll(req.headers)
      ..bodyBytes = utf8.encode(body);
    log?.add((req.method, req.url.toString()));
    final res = await handler(r);
    return http.StreamedResponse(
        Stream.value(res.bodyBytes), res.statusCode,
        headers: res.headers);
  });
}

void main() {
  test('mkdirp 逐级 MKCOL，405 已存在视为成功', () async {
    final log = <(String, String)>[];
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com/',
      username: 'u',
      password: 'p',
      client: _mock((req) async {
        if (req.method == 'MKCOL' && req.url.path.contains('comic-forge/backup')) {
          return http.Response('', 405); // 二级目录已存在
        }
        return http.Response('', 201);
      }, log: log),
    );
    await client.mkdirp('/comic-forge/backup');
    final mk = log.where((e) => e.$1 == 'MKCOL').toList();
    expect(mk, hasLength(2));
    expect(mk[0].$2, 'https://dav.example.com/comic-forge');
    expect(mk[1].$2, 'https://dav.example.com/comic-forge/backup');
    // Basic 认证头
    final auth = base64Encode(utf8.encode('u:p'));
    expect(log.any((e) => e.$1 == 'MKCOL'), isTrue);
  });

  test('MKCOL 4xx（非405）抛 WebDavException', () async {
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com',
      client: _mock((req) async => http.Response('', 401)),
    );
    await expectLater(client.mkdirp('/x'), throwsA(isA<WebDavException>()));
  });

  test('PUT 上传字节 + 认证头；5xx 报错', () async {
    http.Request? seen;
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com',
      username: 'a',
      password: 'b',
      client: _mock((req) async {
        seen = req;
        return http.Response('', 201);
      }),
    );
    await client.putBytes('/cf/backup.json', utf8.encode('{"v":1}'));
    expect(seen!.method, 'PUT');
    expect(seen!.url.toString(), 'https://dav.example.com/cf/backup.json');
    expect(seen!.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('a:b'))}');
    expect(seen!.bodyBytes, utf8.encode('{"v":1}'));

    final bad = WebDavClient(
      baseUrl: 'https://dav.example.com',
      client: _mock((req) async => http.Response('', 502)),
    );
    await expectLater(
        bad.putBytes('/x.json', [1]), throwsA(isA<WebDavException>()));
  });

  test('GET 下载 / 404 明确报远端不存在', () async {
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com',
      client: _mock((req) async {
        if (req.url.path.endsWith('backup.json')) {
          return http.Response.bytes(utf8.encode('payload'), 200);
        }
        return http.Response('', 404);
      }),
    );
    expect(utf8.decode(await client.getBytes('/cf/backup.json')), 'payload');
    await expectLater(client.getBytes('/none.json'),
        throwsA(predicate<WebDavException>((e) => e.message.contains('不存在'))));
  });

  test('路径校验：拒绝 .. 穿越与非 http 地址', () {
    final client = WebDavClient(baseUrl: 'https://dav.example.com');
    expect(() => client.getBytes('/../etc/passwd'), throwsFormatException);
    expect(() => WebDavClient(baseUrl: 'ftp://x'), throwsFormatException);
  });
}
