import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

SourceRuntime _runtime(
  FakeFetcher fetcher, {
  String sourceId = 'reader-images',
}) => SourceRuntime(
  source: ComicSource.fromJson({
    'id': sourceId,
    'url': 'https://reader.example',
    'rules': {'contentUrl': '.page@src'},
  }),
  fetcher: fetcher,
);

void main() {
  final service = SourceService.instance;
  tearDown(() => service.adBlock = null);

  test('修改、停用或清除广告规则后，缓存章节按当前规则恢复图片且不重复抓取', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    final fetcher = FakeFetcher(
      (_) =>
          '<img class="page" src="/page-1.png">'
          '<img class="page" src="/advert.png">'
          '<img class="page" src="/page-2.png">',
    );
    final runtime = _runtime(fetcher);
    const chapter = 'https://reader.example/rule-changes';
    const urls = [
      'https://reader.example/page-1.png',
      'https://reader.example/advert.png',
      'https://reader.example/page-2.png',
    ];

    expect(await service.imagesFor(runtime, chapter), urls);
    await state.setAdBlock('{"urlRules":["advert"]}');
    expect(await service.imagesFor(runtime, chapter), [urls[0], urls[2]]);
    await state.setAdBlock('{"urlRules":["page-2"]}');
    expect(await service.imagesFor(runtime, chapter), [urls[0], urls[1]]);
    await state.setAdBlock('{"enabled":false,"urlRules":["page"]}');
    expect(await service.imagesFor(runtime, chapter), urls);
    await state.setAdBlock(null);
    expect(await service.imagesFor(runtime, chapter), urls);
    expect(fetcher.requests, hasLength(1));
  });

  test('预取和阅读共享在途请求，完成时使用最新规则并保留原始图片', () async {
    final response = Completer<String>();
    final fetcher = FakeFetcher((_) => response.future);
    final runtime = _runtime(fetcher);
    const chapter = 'https://reader.example/prefetch-rules';
    service.adBlock = AdBlockRules.fromJson({
      'urlRules': ['advert'],
    });

    service.prefetchImages(runtime, chapter);
    final pending = service.imagesFor(runtime, chapter);
    service.adBlock = AdBlockRules.fromJson({
      'urlRules': ['page-1'],
    });
    response.complete(
      '<img class="page" src="/page-1.png">'
      '<img class="page" src="/advert.png">',
    );

    expect(await pending, ['https://reader.example/advert.png']);
    service.adBlock = null;
    expect(await service.imagesFor(runtime, chapter), [
      'https://reader.example/page-1.png',
      'https://reader.example/advert.png',
    ]);
    expect(fetcher.requests, hasLength(1));
  });

  test('不同源的相同章节地址分别预取和缓存', () async {
    final firstFetcher = FakeFetcher(
      (_) => '<img class="page" src="/first-source.png">',
    );
    final secondFetcher = FakeFetcher(
      (_) => '<img class="page" src="/second-source.png">',
    );
    final first = _runtime(firstFetcher, sourceId: 'images-first');
    final second = _runtime(secondFetcher, sourceId: 'images-second');
    const chapter = 'https://reader.example/shared-url';

    expect(await service.imagesFor(first, chapter), [
      'https://reader.example/first-source.png',
    ]);
    service.prefetchImages(second, chapter);
    expect(await service.imagesFor(second, chapter), [
      'https://reader.example/second-source.png',
    ]);
    expect(await service.imagesFor(first, chapter), [
      'https://reader.example/first-source.png',
    ]);
    expect(firstFetcher.requests, hasLength(1));
    expect(secondFetcher.requests, hasLength(1));
  });

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
