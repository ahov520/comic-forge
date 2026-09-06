import 'package:engine/src/models/comic_source.dart';
import 'package:engine/src/models/content.dart';
import 'package:engine/src/models/source_health.dart';
import 'package:engine/src/net/fetcher.dart';
import 'package:engine/src/source_health.dart';
import 'package:engine/src/source_runtime.dart';
import 'package:test/test.dart';

import 'source_runtime_test.dart' show FakeFetcher, buildSource;

void main() {
  group('SourceHealth', () {
    test('失败后标为 unhealthy，成功后恢复', () {
      final h = SourceHealth();
      expect(h.isDefault, isTrue);
      expect(h.isUnhealthy, isFalse);

      h.markFailure(FetchException('HTTP 403 for https://dead.example'));
      expect(h.isUnhealthy, isTrue);
      expect(h.failCount, 1);
      expect(h.lastError, contains('403'));
      expect(h.lastCheckedMs, isNotNull);

      h.markSuccess();
      expect(h.isHealthy, isTrue);
      expect(h.isUnhealthy, isFalse);
      expect(h.failCount, 0);
      expect(h.lastError, isEmpty);
    });

    test('超长错误信息截断', () {
      final h = SourceHealth();
      h.markFailure('x' * 400);
      expect(h.lastError.length, lessThanOrEqualTo(241));
      expect(h.lastError.endsWith('…'), isTrue);
    });

    test('JSON 往返', () {
      final h = SourceHealth()..markFailure('down');
      final back = SourceHealth.fromJson(h.toJson());
      expect(back.isUnhealthy, isTrue);
      expect(back.lastError, 'down');
      expect(back.failCount, 1);

      final src = buildSource()..health.markFailure('timeout');
      final restored = ComicSource.fromJson(src.toJson());
      expect(restored.health.isUnhealthy, isTrue);
      expect(restored.health.lastError, 'timeout');
    });
  });

  group('SourceGuard / IsolatedSearch', () {
    test('单源失败不抛、记 unhealthy', () async {
      final src = buildSource();
      final v = await SourceGuard.run(src, () async => throw FetchException('down'));
      expect(v, isNull);
      expect(src.health.isUnhealthy, isTrue);
    });

    test('track 失败仍抛出并记 unhealthy', () async {
      final src = buildSource();
      await expectLater(
        SourceGuard.track(src, () async => throw StateError('bad')),
        throwsA(isA<StateError>()),
      );
      expect(src.health.isUnhealthy, isTrue);
    });

    test('聚合搜索：坏源失败不影响好源结果', () async {
      final good = buildSource()..id = 'good'..name = '好源';
      final bad = ComicSource(id: 'bad', name: '坏源')
        ..rules.searchUrl = 'https://dead.example/search';
      final disabled = ComicSource(id: 'off', name: '关', enabled: false)
        ..rules.searchUrl = 'https://off.example/search';
      var searched = <String>[];

      final result = await IsolatedSearch.run(
        sources: [good, bad, disabled],
        search: (s) async {
          searched.add(s.id);
          if (s.id == 'bad') throw FetchException('down');
          return Paged([Book(sourceId: s.id, name: '海贼王', bookUrl: '/1')]);
        },
      );

      expect(result.items.map((b) => b.name), ['海贼王']);
      expect(result.failedNames, ['坏源']);
      expect(searched.toSet(), {'good', 'bad'});
      expect(good.health.isHealthy, isTrue);
      expect(bad.health.isUnhealthy, isTrue);
      expect(disabled.health.status, SourceHealthStatus.unknown);
    });

    test('缺 searchUrl 或已禁用的源不参与聚合', () async {
      final empty = ComicSource(id: 'empty', name: '空');
      final off = ComicSource(id: 'off', enabled: false)
        ..rules.searchUrl = 'https://x';
      final result = await IsolatedSearch.run(
        sources: [empty, off],
        search: (_) async => throw StateError('不应被调用'),
      );
      expect(result.items, isEmpty);
      expect(result.failedNames, isEmpty);
      expect(empty.health.isDefault, isTrue);
    });
  });

  group('SourceRuntime.probe', () {
    test('命中源站点 url', () async {
      final fetcher = FakeFetcher({'https://m.example.com': '<html>ok</html>'});
      final rt = SourceRuntime(source: buildSource(), fetcher: fetcher);
      await rt.probe();
      expect(fetcher.requested, contains('https://m.example.com'));
    });

    test('站点不可达则抛 FetchException', () async {
      final rt = SourceRuntime(source: buildSource(), fetcher: FakeFetcher({}));
      await expectLater(rt.probe(), throwsA(isA<FetchException>()));
    });

    test('无 url 时回退 searchUrl', () async {
      final src = ComicSource(id: 'x', name: '无主页')
        ..rules.searchUrl = 'https://m.example.com/search?q={{key}}';
      final fetcher = FakeFetcher({
        'https://m.example.com/search?q=1': '<html>ok</html>',
      });
      await SourceRuntime(source: src, fetcher: fetcher).probe();
      expect(fetcher.requested.single, contains('/search?q=1'));
    });
  });
}
