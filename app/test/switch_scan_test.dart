import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fetcher.dart';

const _page =
    '<div class="item"><a class="t" href="/c/1">同名书</a></div>'
    '<div class="item"><a class="t" href="/c/2">别的书</a></div>';

ComicSource _source(String id) => ComicSource.fromJson({
  'id': id,
  'name': '源$id',
  'url': 'https://$id.example',
  'rules': {
    'searchUrl': '/search',
    'searchList': '.item',
    'searchName': '.t@text',
    'searchBookUrl': '.t@href',
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SourceService service;
  late List<ComicSource> sources;
  late Book book;
  late FakeFetcher fetcher;
  late FutureOr<String> Function(Uri uri) respond;

  setUp(() {
    service = SourceService.instance;
    sources = [_source('current'), _source('first'), _source('second')];
    book = Book(name: '同名书', sourceId: 'current', bookUrl: '/book');
    respond = (_) => _page;
    fetcher = FakeFetcher((uri) => respond(uri));
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });
  tearDown(() {
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  test('换源优先同名书，同一候选范围并发与后续调用共享请求', () async {
    final pending = service.scanSwitchTargets(book: book, allSources: sources);
    final concurrent = service.scanSwitchTargets(
      book: book,
      allSources: sources,
    );
    final results = await Future.wait([pending, concurrent]);
    for (final result in results) {
      expect(
        result.map((entry) => entry.$1.id),
        unorderedEquals(['first', 'second']),
      );
      expect(result.every((entry) => entry.$2.name == '同名书'), isTrue);
    }
    expect(fetcher.requests, hasLength(2));
    sources[1].failCount = 2;
    sources[2].weight = 10;
    await service.scanSwitchTargets(book: book, allSources: sources);
    expect(fetcher.requests, hasLength(2), reason: '健康、权重变化不重复扫描');
  });

  test('禁用、删除与新增源后重新扫描只返回当前可用候选', () async {
    await service.scanSwitchTargets(book: book, allSources: sources);
    sources[1].enabled = false;
    final enabled = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
    );
    expect(enabled.map((entry) => entry.$1.id), ['second']);

    sources.removeLast();
    final requests = fetcher.requests.length;
    expect(
      await service.scanSwitchTargets(book: book, allSources: sources),
      isEmpty,
    );
    expect(fetcher.requests, hasLength(requests));
    sources.add(_source('third'));
    final added = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
    );
    expect(added.map((entry) => entry.$1.id), ['third']);
  });

  test('修改候选源后丢弃旧候选缓存并使用新地址', () async {
    await service.scanSwitchTargets(book: book, allSources: sources);
    sources[2] = ComicSource.fromJson({
      ...sources[2].toJson(),
      'url': 'https://edited.example',
    });
    final result = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
    );
    final edited = result.singleWhere((entry) => entry.$1.id == 'second');
    expect(edited.$2.bookUrl, 'https://edited.example/c/1');
  });

  test('不同扫描上限分别返回对应范围，再次扫描相同范围复用请求', () async {
    final limited = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
      maxSources: 1,
    );
    expect(limited.map((entry) => entry.$1.id), ['first']);
    final expanded = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
      maxSources: 2,
    );
    expect(
      expanded.map((entry) => entry.$1.id),
      unorderedEquals(['first', 'second']),
    );
    final count = fetcher.requests.length;
    await service.scanSwitchTargets(
      book: book,
      allSources: sources,
      maxSources: 2,
    );
    expect(fetcher.requests, hasLength(count));
  });

  test('旧范围的在途扫描晚到不会覆盖当前候选缓存', () async {
    final response = Completer<String>();
    respond = (uri) => uri.host == 'first.example' ? response.future : _page;
    final old = service.scanSwitchTargets(
      book: book,
      allSources: sources.take(2).toList(),
    );
    final current = service.scanSwitchTargets(
      book: book,
      allSources: [sources[0], sources[2]],
    );
    response.complete(_page);
    expect((await current).single.$1.id, 'second');
    expect((await old).single.$1.id, 'first');
    final result = await service.scanSwitchTargets(
      book: book,
      allSources: [sources[0], sources[2]],
    );
    expect(result.single.$1.id, 'second');
    expect(fetcher.requests, hasLength(2));
  });

  test('部分源失败仍返回可用命中，全部失败则允许下一次重试', () async {
    respond = (_) => throw FetchException('offline');
    await expectLater(
      service.scanSwitchTargets(book: book, allSources: sources),
      throwsStateError,
    );
    respond = (uri) {
      if (uri.host == 'first.example') throw FetchException('offline');
      return _page;
    };
    final result = await service.scanSwitchTargets(
      book: book,
      allSources: sources,
    );
    expect(result.single.$1.id, 'second');
    expect(fetcher.requests, hasLength(4));
    await service.scanSwitchTargets(book: book, allSources: sources);
    expect(fetcher.requests, hasLength(4));
  });

  test('旧扫描失败不删除新范围已经成功的缓存', () async {
    final response = Completer<String>();
    respond = (uri) => uri.host == 'first.example' ? response.future : _page;
    final oldError = expectLater(
      service.scanSwitchTargets(
        book: book,
        allSources: sources.take(2).toList(),
      ),
      throwsStateError,
    );
    final currentSources = [sources[0], sources[2]];
    final current = await service.scanSwitchTargets(
      book: book,
      allSources: currentSources,
    );
    expect(current.single.$1.id, 'second');
    response.completeError(FetchException('late failure'));
    await oldError;
    final cached = await service.scanSwitchTargets(
      book: book,
      allSources: currentSources,
    );
    expect(cached.single.$1.id, 'second');
    expect(fetcher.requests, hasLength(2));
  });
}
