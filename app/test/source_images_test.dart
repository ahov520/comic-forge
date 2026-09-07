import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fetcher.dart';

SourceRuntime _runtime(FakeFetcher fetcher) => SourceRuntime(
  source: ComicSource.fromJson({
    'id': 'reader-images',
    'url': 'https://reader.example',
    'rules': {'contentUrl': '.page@src'},
  }),
  fetcher: fetcher,
);

void main() {
  final service = SourceService.instance;

  test('章节请求失败后可重试，成功后仍复用缓存', () async {
    var attempts = 0;
    final runtime = _runtime(
      FakeFetcher((_) {
        if (++attempts == 1) throw StateError('offline');
        return '<img class="page" src="/page-1.png">';
      }),
    );
    const url = 'https://reader.example/retry';

    await expectLater(service.imagesFor(runtime, url), throwsStateError);
    expect(await service.imagesFor(runtime, url), [
      'https://reader.example/page-1.png',
    ]);
    await service.imagesFor(runtime, url);
    expect(attempts, 2);
  });

  test('显式重试重新获取空章节，并替换原缓存', () async {
    var attempts = 0;
    final runtime = _runtime(
      FakeFetcher(
        (_) => ++attempts == 1
            ? '<html></html>'
            : '<img class="page" src="/new-page.png">',
      ),
    );
    const url = 'https://reader.example/empty';

    expect(await service.imagesFor(runtime, url), isEmpty);
    expect(await service.imagesFor(runtime, url, refresh: true), [
      'https://reader.example/new-page.png',
    ]);
    expect(await service.imagesFor(runtime, url), [
      'https://reader.example/new-page.png',
    ]);
    expect(attempts, 2);
  });

  test('旧请求晚到的失败不会清掉重试成功的缓存', () async {
    final firstResponse = Completer<String>();
    var attempts = 0;
    final runtime = _runtime(
      FakeFetcher(
        (_) => ++attempts == 1
            ? firstResponse.future
            : '<img class="page" src="/fresh.png">',
      ),
    );
    const url = 'https://reader.example/race';

    final first = service.imagesFor(runtime, url);
    final firstError = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(await service.imagesFor(runtime, url, refresh: true), [
      'https://reader.example/fresh.png',
    ]);
    firstResponse.completeError(StateError('late failure'));
    await firstError;
    expect(await service.imagesFor(runtime, url), [
      'https://reader.example/fresh.png',
    ]);
    expect(attempts, 2);
  });

  testWidgets('预热失败静默结束，后续仍可重新加载', (tester) async {
    var attempts = 0;
    final runtime = _runtime(
      FakeFetcher((_) {
        if (++attempts == 1) throw StateError('prefetch failed');
        return '<html></html>';
      }),
    );
    const url = 'https://reader.example/prefetch-failure';
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          service.precacheLeadingImages(context, runtime, url);
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(await service.imagesFor(runtime, url), isEmpty);
    expect(attempts, 2);
  });
}
