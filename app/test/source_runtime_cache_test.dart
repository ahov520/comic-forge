import 'dart:async';

import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_fetcher.dart';

ComicSource _source(String version) => ComicSource.fromJson({
  'id': 'editable-source',
  'name': '可编辑源',
  'url': 'https://$version.example',
  'rules': {
    'searchUrl': '/search',
    'searchList': '.item',
    'searchName': '.$version@text',
    'searchBookUrl': '.$version@href',
    'contentUrl': '.$version-image@src',
  },
});

const _page =
    '<div class="item">'
    '<a class="old" href="/old-book">旧规则漫画</a>'
    '<a class="new" href="/new-book">新规则漫画</a></div>'
    '<img class="old-image" src="/old-page.png">'
    '<img class="new-image" src="/new-page.png">';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SourceService service;
  late AppState state;
  late FakeFetcher fetcher;

  setUp(() async {
    service = SourceService.instance;
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.addSourceManual(_source('old'));
    fetcher = FakeFetcher((_) => _page);
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (source) =>
        SourceRuntime(source: source, fetcher: fetcher);
  });
  tearDown(() {
    state.dispose();
    service.debugRuntimeOverride = null;
    service.debugClearSwitchCache();
  });

  test('保存源的新地址和规则后，搜索与缓存章节立即使用新定义', () async {
    const chapter = 'https://shared.example/edited-chapter';
    final oldRuntime = service.runtimeFor(state.sources.single);
    expect((await oldRuntime.search('漫画')).items.single.name, '旧规则漫画');
    expect(await service.imagesFor(oldRuntime, chapter), [
      'https://shared.example/old-page.png',
    ]);

    await state.addSourceManual(_source('new'));
    final updated = service.runtimeFor(state.sources.single);
    final found = (await updated.search('漫画')).items.single;
    expect(found.name, '新规则漫画');
    expect(found.bookUrl, 'https://new.example/new-book');
    expect(await service.imagesFor(updated, chapter), [
      'https://shared.example/new-page.png',
    ]);
    expect(fetcher.requests, hasLength(4));

    await state.reportSourceHealth([state.sources.single.id], const {});
    await state.toggleSource(state.sources.single.id);
    await state.toggleSource(state.sources.single.id);
    expect(
      await service.imagesFor(
        service.runtimeFor(state.sources.single),
        chapter,
      ),
      ['https://shared.example/new-page.png'],
    );
    expect(fetcher.requests, hasLength(4), reason: '健康与启停状态变化仍复用图片缓存');
  });

  test('规则更新期间旧请求晚到不会影响新运行时的章节缓存', () async {
    const chapter = 'https://shared.example/edited-pending';
    final response = Completer<String>();
    var attempts = 0;
    fetcher = FakeFetcher((_) => ++attempts == 1 ? response.future : _page);
    final oldRuntime = service.runtimeFor(state.sources.single);
    final oldImages = service.imagesFor(oldRuntime, chapter);
    await state.addSourceManual(_source('new'));
    final updated = service.runtimeFor(state.sources.single);
    final currentImages = service.imagesFor(updated, chapter);
    response.complete(_page);

    expect(await currentImages, ['https://shared.example/new-page.png']);
    expect(await oldImages, ['https://shared.example/old-page.png']);
    expect(await service.imagesFor(updated, chapter), [
      'https://shared.example/new-page.png',
    ]);
    expect(attempts, 2);
  });
}
