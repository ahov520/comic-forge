import 'package:engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('DomainBlocklist.normalize / hostOf', () {
    test('裸域名、URL、协议相对、通配与端口认证信息', () {
      const expected = 'evil.com';
      for (final raw in [
        'evil.com',
        'EVIL.COM',
        'evil.com.',
        '*.evil.com',
        'https://evil.com/path?q=1#x',
        'http://evil.com:8080/a',
        '//evil.com/cdn',
        'evil.com/path',
        'https://user:pass@evil.com:443/x',
      ]) {
        expect(DomainBlocklist.normalize(raw), expected, reason: raw);
        expect(DomainBlocklist.hostOf(raw), expected, reason: raw);
      }
    });

    test('非法输入返回 null', () {
      for (final raw in [
        '',
        '   ',
        '*',
        '*.',
        '.',
        'http://',
        'https://',
        '/only/path',
        'javascript:alert(1)',
        'mailto:user@evil.com',
        'file:///sdcard/page.png',
        'not a host',
        'evil',
      ]) {
        expect(DomainBlocklist.normalize(raw), isNull, reason: raw);
      }
    });

    test('IPv4 合法则保留，越界拒绝', () {
      expect(DomainBlocklist.normalize('1.2.3.4'), '1.2.3.4');
      expect(DomainBlocklist.normalize('https://127.0.0.1:9/x'), '127.0.0.1');
      expect(DomainBlocklist.normalize('1.2.3.256'), isNull);
    });
  });

  group('DomainBlocklist.match', () {
    test('整域含子域，不误伤后缀或兄弟域', () {
      final list = DomainBlocklist(['evil.com']);
      expect(list.match('https://evil.com/a.jpg'), 'evil.com');
      expect(list.match('https://www.evil.com/a'), 'evil.com');
      expect(list.match('https://CDN.Evil.COM/img'), 'evil.com');
      expect(list.match('https://a.b.evil.com/'), 'evil.com');
      expect(list.matches('https://not-evil.com/'), isFalse);
      expect(list.matches('https://evilevil.com/'), isFalse);
      expect(list.matches('https://evil.com.attacker.net/'), isFalse);
      expect(list.matches('https://ok.example/'), isFalse);
      expect(list.matches('file:///cache/page.png'), isFalse);
    });

    test('更具体的条目不向上拦截父域', () {
      final list = DomainBlocklist(['www.evil.com']);
      expect(list.matches('https://www.evil.com/a'), isTrue);
      expect(list.matches('https://img.www.evil.com/a'), isTrue);
      expect(list.matches('https://evil.com/a'), isFalse);
      expect(list.matches('https://cdn.evil.com/a'), isFalse);
    });

    test('add/remove/replaceAll 去重并忽略坏条目', () {
      final list = DomainBlocklist(['https://B.com/x', 'b.com', '']);
      expect(list.hosts, ['b.com']);
      expect(list.add('*.b.com'), isFalse);
      expect(list.add('not a host'), isFalse);
      expect(list.add('cdn.other.net'), isTrue);
      expect(list.hosts, ['b.com', 'cdn.other.net']);
      expect(list.remove('https://cdn.other.net/z'), isTrue);
      expect(list.hosts, ['b.com']);
      list.replaceAll(['OK.example', 'bad']);
      expect(list.hosts, ['ok.example']);
    });
  });

  group('DomainBlocklist.matchRedirects', () {
    test('相对 Location 与协议相对地址按当前 URL 解析', () {
      final list = DomainBlocklist(['tracker.example']);
      expect(
        list.matchRedirects('https://safe.example/start', [
          '/go',
          '//tracker.example/pixel',
        ]),
        'tracker.example',
      );
      expect(
        list.matchRedirects('https://safe.example/start', [
          'https://safe.example/next',
          '/still-safe',
        ]),
        isNull,
      );
    });

    test('起始 URL 已命中则不再看后续跳转', () {
      final list = DomainBlocklist(['evil.com']);
      expect(
        list.matchRedirects('https://evil.com/a', ['https://ok.example/b']),
        'evil.com',
      );
    });

    test('绝对跳转到被拦主机', () {
      final list = DomainBlocklist(['sink.example']);
      expect(
        list.matchRedirects('https://ok.example/a', [
          'https://sink.example/collect?u=1',
        ]),
        'sink.example',
      );
    });
  });

  group('NetworkPolicy / PolicyFetcher', () {
    test('assertAllowed 抛出可读的 BlockedHostException', () {
      final policy = NetworkPolicy(domains: ['blocked.example']);
      expect(policy.isBlocked('https://cdn.blocked.example/x'), isTrue);
      expect(
        () => policy.assertAllowed('https://blocked.example/x'),
        throwsA(
          isA<BlockedHostException>()
              .having((e) => e.host, 'host', 'blocked.example')
              .having(
                (e) => e.userMessage,
                'userMessage',
                '域名已被屏蔽：blocked.example',
              ),
        ),
      );
      policy.assertAllowed('https://ok.example/x');
    });

    test('PolicyFetcher 在委托前拦截，不发起下游请求', () async {
      var called = false;
      final inner = _RecordingFetcher(() => called = true);
      final fetcher = PolicyFetcher(
        inner: inner,
        policy: NetworkPolicy(domains: ['no.example']),
      );
      await expectLater(
        fetcher.getBytes('https://no.example/a'),
        throwsA(isA<BlockedHostException>()),
      );
      await expectLater(
        fetcher.send(SourceRequest(url: 'https://no.example/b')),
        throwsA(isA<BlockedHostException>()),
      );
      expect(called, isFalse);
      await fetcher.getBytes('https://ok.example/a');
      expect(called, isTrue);
    });
  });

  group('HttpFetcher redirects + policy', () {
    test('跟随相对跳转并拦截目标主机', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/start') {
          return http.Response('', 302, headers: {'location': '/hop'});
        }
        if (request.url.path == '/hop') {
          return http.Response(
            '',
            301,
            headers: {'location': '//sink.example/end'},
          );
        }
        return http.Response('secret', 200);
      });
      addTearDown(client.close);
      final policy = NetworkPolicy(domains: ['sink.example']);
      final fetcher = HttpFetcher(client: client, policy: policy);
      await expectLater(
        fetcher.getBytes('https://safe.example/start'),
        throwsA(
          isA<BlockedHostException>().having(
            (e) => e.host,
            'host',
            'sink.example',
          ),
        ),
      );
      expect(requested.map((u) => u.toString()), [
        'https://safe.example/start',
        'https://safe.example/hop',
      ]);
    });

    test('跳转链未命中则返回最终响应', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/a') {
          return http.Response('', 302, headers: {'location': '/b'});
        }
        return http.Response('ok-body', 200);
      });
      addTearDown(client.close);
      final fetcher = HttpFetcher(client: client, policy: NetworkPolicy());
      expect(await fetcher.getString('https://ok.example/a'), 'ok-body');
    });

    test('起始 URL 被拦则不发请求', () async {
      var hits = 0;
      final client = MockClient((request) async {
        hits++;
        return http.Response('nope', 200);
      });
      addTearDown(client.close);
      final fetcher = HttpFetcher(
        client: client,
        policy: NetworkPolicy(domains: ['evil.com']),
      );
      await expectLater(
        fetcher.send(SourceRequest(url: 'https://evil.com/x')),
        throwsA(isA<BlockedHostException>()),
      );
      expect(hits, 0);
    });
  });
}

class _RecordingFetcher implements Fetcher {
  _RecordingFetcher(this.onCall);
  final void Function() onCall;

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? charset,
  }) async {
    onCall();
    return 'ok';
  }

  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    onCall();
    return const [];
  }

  @override
  Future<List<int>> send(
    SourceRequest request, {
    Map<String, String>? headers,
  }) => getBytes(request.url, headers: headers);
}
