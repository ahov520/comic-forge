import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comic_forge/services/download_store.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/download_queue.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_test_image.dart';
import 'support/fake_fetcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DownloadStore store;
  final queues = <DownloadQueue>[];
  late Book book;
  late List<Chapter> chapters;

  DownloadQueue queue({
    Future<DownloadImages> Function(Book, Chapter)? images,
    Future<List<int>> Function(String, Map<String, String>)? fetch,
  }) {
    final result = DownloadQueue(
      sourceFor: (_) => null,
      store: store,
      loadImages:
          images ??
          (_, chapter) async => (
            urls: ['${chapter.url}/1.png', '${chapter.url}/2.png'],
            headers: {'Referer': chapter.url},
          ),
      fetchBytes: fetch ?? (_, _) async => downloadTestImage(),
    );
    queues.add(result);
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'comic-forge-download-test-',
    );
    store = DownloadStore(directory: () async => directory);
    book = Book(
      sourceId: 'downloads',
      name: '离线漫画',
      bookUrl: 'https://download.example/book',
    );
    chapters = List.generate(
      3,
      (i) => Chapter(
        title: '第${i + 1}话',
        url: 'https://download.example/c${i + 1}',
      ),
    );
  });

  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
      await queue.idle;
    }
    queues.clear();
    await directory.delete(recursive: true);
  });

  test('多选去重、按章节顺序排队，完成后跨重启断网读取真实文件', () async {
    final downloads = queue();
    expect(await downloads.enqueue(book, chapters, [2, 0, 0]), 2);
    await downloads.idle;
    expect(downloads.tasks.map((t) => t.chapter.url), [
      chapters[0].url,
      chapters[2].url,
    ]);
    expect(
      downloads.tasks.map((t) => t.status),
      everyElement(DownloadStatus.completed),
    );
    expect(await downloads.enqueue(book, chapters, [0, 2]), 0);
    final local = (await downloads.offlineImages(book, chapters[0]))!;
    expect(local.length, 2);
    expect(
      await File.fromUri(Uri.parse(local.first)).readAsBytes(),
      downloadTestImage(),
    );

    var networkCalls = 0;
    final restored = queue(
      images: (_, _) async {
        networkCalls++;
        throw StateError('offline');
      },
      fetch: (_, _) async {
        networkCalls++;
        throw StateError('offline');
      },
    );
    await restored.load();
    expect(await restored.offlineImages(book, chapters[0]), local);
    expect(restored.offlineCatalogFor(book.bookUrl)?.chapters.length, 3);
    expect(networkCalls, 0);
  });

  test('部分图片失败不阻塞其它话，失败重试只补缺图并保留请求头', () async {
    var failSecond = true;
    final calls = <String, int>{};
    final downloads = queue(
      fetch: (url, headers) async {
        calls.update(url, (count) => count + 1, ifAbsent: () => 1);
        expect(headers['Referer'], url.substring(0, url.lastIndexOf('/')));
        if (url == '${chapters[0].url}/2.png' && failSecond) {
          throw StateError('offline');
        }
        return downloadTestImage();
      },
    );
    await downloads.enqueue(book, chapters, [0, 1]);
    await downloads.idle;
    final failed = downloads.taskFor(book, chapters[0])!;
    expect(failed.status, DownloadStatus.failed);
    expect(failed.downloadedPages, 1);
    expect(
      downloads.taskFor(book, chapters[1])?.status,
      DownloadStatus.completed,
    );
    failSecond = false;
    await downloads.retryFailed();
    await downloads.idle;
    expect(failed.status, DownloadStatus.completed);
    expect(calls['${chapters[0].url}/1.png'], 1);
    expect(calls['${chapters[0].url}/2.png'], 2);
    expect(failed.error, isNull);
  });

  test('最后一张图落盘后中断完成标记，重启断网仍识别为可阅读', () async {
    final downloads = queue();
    await downloads.enqueue(book, chapters, [0]);
    await downloads.idle;
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('cf.downloadQueue')!)
            as Map<String, dynamic>;
    (saved['tasks'] as List).single['status'] = 'downloading';
    await prefs.setString('cf.downloadQueue', jsonEncode(saved));
    var networkCalls = 0;
    final restored = queue(
      images: (_, _) async {
        networkCalls++;
        throw StateError('offline');
      },
    );
    await restored.load();
    await restored.idle;
    expect(restored.tasks.single.status, DownloadStatus.completed);
    expect((await restored.offlineImages(book, chapters[0]))?.length, 2);
    expect(networkCalls, 0);
  });

  test('进程中断后恢复下载，已经落盘的前缀图片不会重复请求', () async {
    final started = Completer<void>();
    final response = Completer<List<int>>();
    final downloads = queue(
      fetch: (url, _) async {
        if (url.endsWith('/2.png')) {
          started.complete();
          return response.future;
        }
        return downloadTestImage();
      },
    );
    addTearDown(() {
      if (!response.isCompleted) response.complete(downloadTestImage());
    });
    await downloads.enqueue(book, chapters, [0]);
    await started.future;
    downloads.dispose();
    queues.remove(downloads);
    response.complete(downloadTestImage());
    await downloads.idle;
    final calls = <String>[];
    final restored = queue(
      fetch: (url, _) async {
        calls.add(url);
        return downloadTestImage();
      },
    );
    await restored.load();
    await restored.idle;
    expect(restored.tasks.single.status, DownloadStatus.completed);
    expect(calls, ['${chapters[0].url}/2.png']);
  });

  test('取消在途任务后晚到的图片不复活任务，随后可重新下载同一话', () async {
    final started = Completer<void>();
    final response = Completer<List<int>>();
    var calls = 0;
    final downloads = queue(
      fetch: (_, _) async {
        if (++calls == 1) {
          started.complete();
          return response.future;
        }
        return downloadTestImage();
      },
    );
    addTearDown(() {
      if (!response.isCompleted) response.complete(downloadTestImage());
    });
    await downloads.enqueue(book, chapters, [0]);
    await started.future;
    final id = downloads.tasks.single.id;
    final removing = downloads.remove(id);
    expect(downloads.tasks, isEmpty);
    final again = downloads.enqueue(book, chapters, [0]);
    response.complete(downloadTestImage());
    await removing;
    expect(await again, 1);
    await downloads.idle;
    expect(downloads.tasks.single.status, DownloadStatus.completed);
    expect((await downloads.offlineImages(book, chapters[0]))?.length, 2);
  });

  test('空章节和伪装成图片的错误页不能标记完成', () async {
    final downloads = queue(
      images: (_, chapter) async => (
        urls: chapter.url == chapters[0].url
            ? <String>[]
            : ['https://download.example/error.png'],
        headers: <String, String>{},
      ),
      fetch: (_, _) async => utf8.encode('<html>Access denied</html>'),
    );
    await downloads.enqueue(book, chapters, [0, 1]);
    await downloads.idle;
    expect(
      downloads.tasks.map((t) => t.status),
      everyElement(DownloadStatus.failed),
    );
    expect(downloads.tasks.map((t) => t.downloadedPages), everyElement(0));
    expect(await downloads.offlineImages(book, chapters[1]), isNull);
  });

  test('文件丢失后标记失败可补下载，删除任务释放文件及离线目录', () async {
    final downloads = queue();
    await downloads.enqueue(book, chapters, [0]);
    await downloads.idle;
    final id = downloads.tasks.single.id;
    final images = (await downloads.offlineImages(book, chapters[0]))!;
    await File.fromUri(Uri.parse(images.last)).delete();
    final calls = <String>[];
    final restored = queue(
      fetch: (url, _) async {
        calls.add(url);
        return downloadTestImage();
      },
    );
    await restored.load();
    expect(restored.tasks.single.status, DownloadStatus.failed);
    expect(restored.tasks.single.downloadedPages, 1);
    await restored.retry(id);
    await restored.idle;
    expect(calls, ['${chapters[0].url}/2.png']);
    await restored.remove(id);
    expect(restored.tasks, isEmpty);
    expect(await File.fromUri(Uri.parse(images.first)).exists(), isFalse);
    expect(restored.offlineCatalogFor(book.bookUrl), isNull);
  });

  test('同名图片按源隔离，离线阅读按当前广告规则过滤原地址', () async {
    final downloads = queue();
    final other = Book(
      sourceId: 'other',
      name: book.name,
      bookUrl: book.bookUrl,
    );
    await downloads.enqueue(book, chapters, [0]);
    await downloads.enqueue(other, chapters, [0]);
    await downloads.idle;
    final first = await downloads.offlineImages(book, chapters[0]);
    final second = await downloads.offlineImages(other, chapters[0]);
    expect(first!.first, isNot(second!.first));
    final filtered = await downloads.offlineImages(
      book,
      chapters[0],
      adBlock: AdBlockRules.fromJson({
        'urlRules': ['2.png'],
      }),
    );
    expect(filtered, [first.first]);
    expect(await downloads.offlineImages(book, chapters[0]), first);
  });

  test('真实源取图携带 headers，源停用后失败可在启用后重试', () async {
    final service = SourceService.instance;
    final source = ComicSource.fromJson({
      'id': book.sourceId,
      'url': 'https://download.example',
      'headers': {
        'Referer': 'https://download.example/book',
        'Cookie': 'test-session',
      },
      'rules': {'contentUrl': '.page@src'},
      'enabled': false,
    });
    service.debugClearSwitchCache();
    service.debugRuntimeOverride = (s) => SourceRuntime(
      source: s,
      fetcher: FakeFetcher((_) => '<img class="page" src="/image.png">'),
    );
    addTearDown(() {
      service.debugRuntimeOverride = null;
      service.debugClearSwitchCache();
    });
    final headers = <Map<String, String>>[];
    final downloads = DownloadQueue(
      sourceFor: (_) => source,
      store: store,
      fetchBytes: (_, h) async {
        headers.add(h);
        return downloadTestImage();
      },
    );
    queues.add(downloads);
    await downloads.enqueue(book, chapters, [0]);
    await downloads.idle;
    expect(downloads.tasks.single.status, DownloadStatus.failed);
    expect(headers, isEmpty);
    source.enabled = true;
    await downloads.retryFailed();
    await downloads.idle;
    expect(downloads.tasks.single.status, DownloadStatus.completed);
    expect(headers.single, source.headers);
  });
}
