import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/download_store.dart';
import '../services/source_service.dart';

enum DownloadStatus { queued, downloading, completed, failed }

class DownloadCatalog {
  DownloadCatalog({
    required this.book,
    required this.chapters,
    required this.at,
  });

  final Book book;
  final List<Chapter> chapters;
  final int at;
  String get key => downloadKey([book.sourceId ?? '', book.bookUrl]);

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'at': at,
  };

  factory DownloadCatalog.fromJson(Map<String, dynamic> json) =>
      DownloadCatalog(
        book: Book.fromJson(json['book'] as Map<String, dynamic>),
        chapters: (json['chapters'] as List)
            .cast<Map<String, dynamic>>()
            .map(Chapter.fromJson)
            .toList(growable: false),
        at: json['at'] as int,
      );
}

class DownloadTask {
  DownloadTask({
    required this.bookKey,
    required this.chapter,
    this.status = DownloadStatus.queued,
    this.imageUrls = const [],
    this.downloadedPages = 0,
    this.error,
  });

  final String bookKey;
  final Chapter chapter;
  String get id => downloadKey([bookKey, chapter.url]);
  DownloadStatus status;
  List<String> imageUrls;
  int downloadedPages;
  String? error;

  Map<String, dynamic> toJson() => {
    'bookKey': bookKey,
    'chapter': chapter.toJson(),
    'status': status.name,
    'imageUrls': imageUrls,
    'downloadedPages': downloadedPages,
    if (error != null) 'error': error,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    bookKey: json['bookKey'] as String,
    chapter: Chapter.fromJson(json['chapter'] as Map<String, dynamic>),
    status:
        DownloadStatus.values
            .where((s) => s.name == json['status'])
            .firstOrNull ??
        DownloadStatus.failed,
    imageUrls: (json['imageUrls'] as List).cast<String>(),
    downloadedPages: json['downloadedPages'] as int? ?? 0,
    error: json['error'] as String?,
  );
}

typedef DownloadImages = ({List<String> urls, Map<String, String> headers});

/// 一次下载一话、一张图片；任务和每张图片进度落盘后才报告完成。
class DownloadQueue extends ChangeNotifier {
  DownloadQueue({
    required this.sourceFor,
    DownloadStore? store,
    this.loadImages,
    this.fetchBytes,
  }) : store = store ?? DownloadStore();

  static const _prefsKey = 'cf.downloadQueue';
  final ComicSource? Function(String) sourceFor;
  final DownloadStore store;
  final Future<DownloadImages> Function(Book, Chapter)? loadImages;
  final Future<List<int>> Function(String, Map<String, String>)? fetchBytes;
  final Map<String, DownloadCatalog> _catalogs = {};
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, Future<void>> _removals = {};
  Future<void>? _loading;
  Future<void>? _worker;
  Future<void>? _writes;
  DownloadTask? _active;
  Completer<void>? _activeDone;
  bool _disposed = false;
  String? storageError;

  bool get supported => !kIsWeb;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.values);
  List<DownloadCatalog> get catalogs {
    final list = _catalogs.values.toList();
    list.sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(list);
  }

  Future<void> get idle async {
    await _writes;
    while (_worker != null) {
      await _worker;
      await _writes;
    }
  }

  DownloadCatalog? catalogFor(DownloadTask task) => _catalogs[task.bookKey];

  DownloadCatalog? catalogForKey(String bookKey) => _catalogs[bookKey];

  Iterable<String> imageUrlsFor(String bookKey) => _tasks.values
      .where((task) => task.bookKey == bookKey)
      .expand((task) => task.imageUrls)
      .where((url) => url.isNotEmpty);

  DownloadTask? taskFor(Book book, Chapter chapter) =>
      _tasks[downloadKey([
        downloadKey([book.sourceId ?? '', book.bookUrl]),
        chapter.url,
      ])];

  DownloadCatalog? offlineCatalogFor(String bookUrl) => _catalogs.values
      .where(
        (catalog) =>
            catalog.book.bookUrl == bookUrl &&
            _tasks.values.any(
              (task) =>
                  task.bookKey == catalog.key &&
                  task.status == DownloadStatus.completed,
            ),
      )
      .firstOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= _restore();

  Future<void> _restore() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_prefsKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      for (final value in json['catalogs'] as List) {
        try {
          final catalog = DownloadCatalog.fromJson(
            value as Map<String, dynamic>,
          );
          if (catalog.book.bookUrl.isNotEmpty) _catalogs[catalog.key] = catalog;
        } catch (_) {
          storageError = '部分下载记录无法恢复';
        }
      }
      for (final value in json['tasks'] as List) {
        DownloadTask? restored;
        try {
          final task = DownloadTask.fromJson(value as Map<String, dynamic>);
          if (!_catalogs.containsKey(task.bookKey) ||
              task.chapter.url.isEmpty) {
            continue;
          }
          restored = task;
          _tasks[task.id] = task;
          if (task.status == DownloadStatus.downloading) {
            task.status = DownloadStatus.queued;
          }
          final wasCompleted = task.status == DownloadStatus.completed;
          if (wasCompleted ||
              (task.status == DownloadStatus.queued &&
                  task.imageUrls.isNotEmpty)) {
            task.downloadedPages = 0;
            for (final url in task.imageUrls) {
              if (await store.contains(task.id, url)) task.downloadedPages++;
            }
            if (task.imageUrls.isNotEmpty &&
                task.downloadedPages == task.imageUrls.length) {
              // 最后一张图已落盘、完成标记尚未写入时退出，也能断网恢复阅读。
              task.status = DownloadStatus.completed;
              task.error = null;
            } else if (wasCompleted) {
              task.status = DownloadStatus.failed;
              task.error = '离线图片缺失，请重试下载';
            }
          }
        } catch (_) {
          if (restored != null) {
            restored.status = DownloadStatus.failed;
            restored.error = '无法读取离线文件，请检查可用空间后重试';
          }
          storageError = '部分下载记录无法恢复';
        }
      }
    } catch (_) {
      storageError = '下载记录无法读取';
    }
    _notify();
    _kick();
  }

  Future<void> _persist() {
    final snapshot = jsonEncode({
      'catalogs': _catalogs.values.map((c) => c.toJson()).toList(),
      'tasks': _tasks.values.map((t) => t.toJson()).toList(),
    });
    final write = (_writes ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_prefsKey, snapshot)) {
        throw StateError('无法保存下载队列');
      }
    });
    _writes = write.catchError((Object error) {
      storageError = '无法保存下载进度，请检查可用空间后重试';
      _notify();
    });
    return write;
  }

  Future<int> enqueue(
    Book book,
    List<Chapter> chapters,
    Iterable<int> indices,
  ) async {
    if (!supported) throw UnsupportedError('当前平台暂不支持离线下载');
    await load();
    final catalog = DownloadCatalog(
      book: Book.fromJson(book.toJson()),
      chapters: List.unmodifiable(
        chapters.map((c) => Chapter.fromJson(c.toJson())),
      ),
      at: DateTime.now().millisecondsSinceEpoch,
    );
    var added = 0;
    for (final index in indices.toSet().toList()..sort()) {
      if (index < 0 ||
          index >= chapters.length ||
          chapters[index].url.isEmpty) {
        continue;
      }
      final task = DownloadTask(
        bookKey: catalog.key,
        chapter: catalog.chapters[index],
      );
      final removing = _removals[task.id];
      if (removing != null) await removing;
      final existing = _tasks[task.id];
      if (existing != null && existing.status != DownloadStatus.failed) {
        continue;
      }
      if (existing == null) {
        _tasks[task.id] = task;
      } else {
        existing.status = DownloadStatus.queued;
        existing.error = null;
      }
      added++;
    }
    if (added == 0) return 0;
    _catalogs[catalog.key] = catalog;
    await _startQueuedTasks();
    return added;
  }

  Future<void> retry(String id) async {
    final task = _tasks[id];
    if (task == null || task.status != DownloadStatus.failed) return;
    task.status = DownloadStatus.queued;
    task.error = null;
    await _startQueuedTasks();
  }

  Future<void> retryFailed() async {
    for (final task in _tasks.values) {
      if (task.status == DownloadStatus.failed) {
        task.status = DownloadStatus.queued;
        task.error = null;
      }
    }
    await _startQueuedTasks();
  }

  Future<int?> usageBytes() async {
    if (!supported) return 0;
    try {
      return await store.usageBytes();
    } catch (_) {
      return null;
    }
  }

  Future<int?> usageBytesForBook(String bookKey) async {
    if (!supported) return 0;
    try {
      var total = 0;
      for (final task in _tasks.values.where(
        (task) => task.bookKey == bookKey,
      )) {
        total += await store.usageBytesForTask(task.id) ?? 0;
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  Future<int> clearCompleted() =>
      _removeMatching((task) => task.status == DownloadStatus.completed);

  Future<int> clearFailed() =>
      _removeMatching((task) => task.status == DownloadStatus.failed);

  Future<int> removeBook(String bookKey) =>
      _removeMatching((task) => task.bookKey == bookKey);

  Future<int> _removeMatching(bool Function(DownloadTask task) test) async {
    await load();
    final ids = _tasks.values.where(test).map((task) => task.id).toList();
    for (final id in ids) {
      await remove(id);
    }
    return ids.length;
  }

  Future<void> _startQueuedTasks() async {
    try {
      await _persist();
    } catch (_) {
      for (final task in _tasks.values) {
        if (task.status == DownloadStatus.queued) {
          task.status = DownloadStatus.failed;
          task.error = '无法保存下载队列，请检查可用空间后重试';
        }
      }
      _notify();
      rethrow;
    }
    storageError = null;
    _notify();
    _kick();
  }

  Future<void> remove(String id) {
    final pending = _removals[id];
    if (pending != null) return pending;
    final task = _tasks.remove(id);
    if (task == null) return Future.value();
    final active = identical(_active, task) ? _activeDone?.future : null;
    final removal = () async {
      try {
        await _persist();
        await active;
        await store.remove(id);
        if (!_tasks.values.any((t) => t.bookKey == task.bookKey)) {
          _catalogs.remove(task.bookKey);
        }
        await _persist();
      } catch (_) {
        task.status = DownloadStatus.failed;
        task.error = '文件删除失败，请重试';
        _tasks[id] = task;
        rethrow;
      } finally {
        _removals.remove(id);
        _notify();
      }
    }();
    _removals[id] = removal;
    _notify();
    return removal;
  }

  bool _current(DownloadTask task) =>
      !_disposed && identical(_tasks[task.id], task);

  void _kick() {
    if (_worker != null || _disposed) return;
    final work = _drain();
    _worker = work;
    unawaited(
      work.whenComplete(() {
        _worker = null;
        if (!_disposed &&
            _tasks.values.any((t) => t.status == DownloadStatus.queued)) {
          _kick();
        }
      }),
    );
  }

  Future<DownloadImages> _resolveImages(Book book, Chapter chapter) async {
    if (loadImages != null) return loadImages!(book, chapter);
    final source = sourceFor(book.sourceId ?? '');
    if (source == null || !source.enabled) throw StateError('来源已停用或移除，请启用后重试');
    final runtime = SourceService.instance.runtimeFor(source);
    final urls = await SourceService.instance.imagesFor(
      runtime,
      chapter.url,
      refresh: true,
    );
    return (
      urls: urls,
      headers: {...source.headers, ...runtime.imageRequestHeaders},
    );
  }

  Future<void> _validateImage(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
      targetWidth: 1,
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<void> _drain() async {
    while (!_disposed) {
      final task = _tasks.values
          .where((t) => t.status == DownloadStatus.queued)
          .firstOrNull;
      if (task == null) return;
      _active = task;
      final done = _activeDone = Completer<void>();
      task.status = DownloadStatus.downloading;
      task.error = null;
      _notify();
      try {
        await _persist();
        if (!_current(task)) continue;
        final catalog = _catalogs[task.bookKey]!;
        final images = await _resolveImages(
          catalog.book,
          task.chapter,
        ).timeout(const Duration(seconds: 30));
        if (!_current(task)) continue;
        if (images.urls.isEmpty) throw StateError('本话没有可下载的图片');
        task.imageUrls = List.unmodifiable(images.urls);
        task.downloadedPages = 0;
        await _persist();
        _notify();
        for (final url in task.imageUrls) {
          if (!_current(task)) break;
          if (!await store.contains(task.id, url)) {
            final bytes =
                await (fetchBytes != null
                        ? fetchBytes!(url, images.headers)
                        : SourceService.instance.fetcher.getBytes(
                            url,
                            headers: images.headers,
                          ))
                    .timeout(const Duration(seconds: 30));
            if (!_current(task)) break;
            await _validateImage(bytes);
            if (!_current(task)) break;
            await store.write(task.id, url, bytes);
          }
          if (!_current(task)) break;
          task.downloadedPages++;
          await _persist();
          _notify();
        }
        if (_current(task)) task.status = DownloadStatus.completed;
      } catch (error) {
        if (_current(task)) {
          task.status = DownloadStatus.failed;
          task.error = switch (error) {
            BlockedHostException e => e.userMessage,
            StateError e => e.message.toString(),
            TimeoutException() => '下载超时，请重试',
            _ => '下载失败，请检查网络和可用空间后重试',
          };
        }
      } finally {
        if (_current(task)) {
          try {
            await _persist();
          } catch (_) {
            task.status = DownloadStatus.failed;
            task.error = '无法保存下载进度，请重试';
          }
          _notify();
        }
        _active = null;
        _activeDone = null;
        done.complete();
      }
    }
  }

  /// 返回本地文件 URI，仍按当前广告规则过滤原始图片地址。
  Future<List<String>?> offlineImages(
    Book book,
    Chapter chapter, {
    AdBlockRules? adBlock,
  }) async {
    await load();
    final task = taskFor(book, chapter);
    if (task == null || task.status != DownloadStatus.completed) return null;
    final urls = adBlock?.filterImages(task.imageUrls) ?? task.imageUrls;
    final images = <String>[];
    for (final url in urls) {
      if (!await store.contains(task.id, url)) {
        task.status = DownloadStatus.failed;
        task.error = '离线图片缺失，请重试下载';
        await _persist();
        _notify();
        return null;
      }
      images.add(await store.imageUri(task.id, url));
    }
    return images;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
