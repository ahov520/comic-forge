import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:engine/engine.dart';

import '../backup_service.dart';
import 'source_update.dart';
import '../services/source_service.dart';
import 'safe_prefs.dart';
import 'scroll_restore.dart';
import 'shelf_updates.dart';
import 'shelf_update_notices.dart';
import 'shelf_update_notifications.dart';
import 'shelf_update_schedule.dart';
import '../services/shelf_update_notifier.dart';
import 'download_queue.dart';
import 'reading_history.dart';
import 'chapter_bookmarks.dart';
import 'reading_stats.dart';
import 'shelf_groups.dart';
import 'shelf_sort.dart';
import 'search_filters.dart';

/// 阅读进度（按书记忆，重启可续读）。
class ReadingProgress {
  ReadingProgress({
    required this.bookUrl,
    required this.sourceId,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.at,
  });

  final String bookUrl;
  final String sourceId;
  final String chapterUrl;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final int at;

  Map<String, dynamic> toJson() => {
    'bookUrl': bookUrl,
    'sourceId': sourceId,
    'chapterUrl': chapterUrl,
    'chapterTitle': chapterTitle,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    'at': at,
  };

  static ReadingProgress fromJson(Map<String, dynamic> j) => ReadingProgress(
    bookUrl: j['bookUrl'] as String? ?? '',
    sourceId: j['sourceId'] as String? ?? '',
    chapterUrl: j['chapterUrl'] as String? ?? '',
    chapterTitle: j['chapterTitle'] as String? ?? '',
    chapterIndex: j['chapterIndex'] as int? ?? 0,
    chapterCount: j['chapterCount'] as int? ?? 0,
    at: j['at'] as int? ?? 0,
  );
}

/// 书籍详情离线缓存（章节目录 stale-while-revalidate）。
class CachedDetail {
  CachedDetail({required this.book, required this.chapters, required this.at});

  final Book book;
  final List<Chapter> chapters;
  final int at;

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'at': at,
  };

  static CachedDetail fromJson(Map<String, dynamic> j) => CachedDetail(
    book: Book.fromJson(j['book'] as Map<String, dynamic>),
    chapters: (j['chapters'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Chapter.fromJson)
        .toList(),
    at: j['at'] as int? ?? 0,
  );
}

/// 全局应用状态：源库、书架、订阅仓库。
class AppState extends ChangeNotifier {
  AppState({
    DownloadQueue? downloadQueue,
    ShelfUpdateSchedule? shelfUpdateSchedule,
    ReadingStats? readingStats,
    ShelfUpdateNotifications? updateNotifications,
    ShelfUpdateNotifier? updateNotifier,
  }) : _downloads = downloadQueue,
       shelfUpdateSchedule = shelfUpdateSchedule ?? ShelfUpdateSchedule(),
       readingStats = readingStats ?? ReadingStats(),
       updateNotifications = updateNotifications ?? ShelfUpdateNotifications(),
       updateNotifier = updateNotifier ?? const NoopShelfUpdateNotifier() {
    shelfGroups.addListener(notifyListeners);
    this.shelfUpdateSchedule.addListener(notifyListeners);
    this.updateNotifications.addListener(notifyListeners);
  }

  final ShelfGroups shelfGroups = ShelfGroups();
  final ShelfUpdateSchedule shelfUpdateSchedule;
  final ReadingStats readingStats;
  final ShelfUpdateNotifications updateNotifications;
  final ShelfUpdateNotifier updateNotifier;
  bool _disposed = false;

  DownloadQueue? _downloads;
  DownloadQueue get downloads => _downloads ??= DownloadQueue(
    sourceFor: (id) => sources.where((source) => source.id == id).firstOrNull,
  );

  @override
  void dispose() {
    _disposed = true;
    readingStats.dispose();
    updateNotifications.removeListener(notifyListeners);
    updateNotifications.dispose();
    shelfUpdateSchedule.removeListener(notifyListeners);
    shelfUpdateSchedule.dispose();
    shelfGroups.removeListener(notifyListeners);
    shelfGroups.dispose();
    _downloads?.dispose();
    super.dispose();
  }

  static const _kSources = 'cf.sources';
  static const _kRepos = 'cf.repos';
  static const _kShelf = 'cf.shelf';
  static const _kShelfChapters = 'cf.shelfChapters';
  static const _kShelfDismissals = 'cf.shelfDismissals';
  static const _kDark = 'cf.dark';
  static const _kProgress = 'cf.progress';
  static const _kReadingHistory = 'cf.readingHistory';
  static const _kChapterBookmarks = 'cf.chapterBookmarks';
  static const _kDetailCache = 'cf.detailCache';
  static const _kReaderBrightness = 'cf.readerBrightness';
  static const _kReaderMode = 'cf.readerMode';
  static const _kReaderVolumeKeys = 'cf.readerVolumeKeys';
  static const _kScrollOffsets = 'cf.scrollOffsets';
  static const _kReaderPages = 'cf.readerPages';
  static const _kLastAutoProbe = 'cf.lastAutoProbe';
  static const _kRepoRefresh = 'cf.repoRefresh';
  static const _kRepoUpdates = 'cf.repoUpdates';
  static const _kAdBlock = 'cf.adBlock';
  static const _kWebDav = 'cf.webdav';
  static const _kSearchHistory = 'cf.searchHistory';
  static const _kSearchFilters = 'cf.searchFilters';
  static const _kShelfSort = 'cf.shelfSort';
  static const _kDomainBlocklist = 'cf.domainBlocklist';
  static const _searchHistoryLimit = 10;
  static const _detailCacheCap = 100;

  /// 启动自动检查间隔：6 小时内不重复检查。
  static const _autoCheckIntervalMs = 6 * 3600 * 1000;

  final List<ComicSource> sources = [];
  final List<String> repos = [];
  final List<Book> shelf = [];
  final Map<String, ShelfChapters> _shelfChapters = {};
  final Map<String, String> _shelfDismissals = {};
  Future<ShelfRefreshResult>? _shelfRefresh;

  bool get checkingShelfUpdates => _shelfRefresh != null;
  final List<String> _searchHistory = [];
  SearchFilters _searchFilters = SearchFilters();
  SearchFilters get searchFilters => _searchFilters;
  ShelfSort _shelfSort = ShelfSort.recentlyRead;
  ShelfSort get shelfSort => _shelfSort;

  /// 最近提交的搜索词（新到旧、去重、最多 10 条）。
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  final Map<String, ReadingProgress> progress = {}; // key: bookUrl
  final List<ReadingHistoryEntry> _readingHistory = [];
  List<ReadingHistoryEntry> get readingHistory =>
      List.unmodifiable(_readingHistory);
  final List<ChapterBookmark> _chapterBookmarks = [];
  int _bookmarkWrite = 0;
  List<ChapterBookmark> get chapterBookmarks =>
      List.unmodifiable(_chapterBookmarks);
  final Map<String, CachedDetail> detailCache = {}; // key: bookUrl
  final Map<String, int> repoLastRefresh = {}; // key: repo url, epoch ms
  final Map<String, RepoUpdateState> repoUpdates = {}; // key: repo url
  /// 广告拦截规则（null = 未启用）。
  AdBlockRules? adBlock;

  /// 当前生效的域名黑名单（规范化主机，与 [SourceService.networkPolicy] 同步）。
  List<String> get blockedDomains => SourceService.instance.networkPolicy.hosts;

  /// WebDAV 配置（url/user/pass/path；明文存本地，仅本机使用）。
  Map<String, String>? webDavConfig;
  bool darkMode = true;

  /// 阅读器遮罩亮度（0.15~1.0，1 = 不加暗）。
  double readerBrightness = 1.0;

  /// 章内滚动位置（key=章节 url；LRU 上限 200 条，跨重启记忆）。
  final Map<String, SavedScrollPosition> scrollOffsets = {};
  // 按最近保存顺序记住至多 200 话的翻页位置，与滚动偏移分别保留。
  final Map<String, int> _readerPages = {};
  int _lastAutoProbeAt = 0;

  /// 阅读模式：scroll = 连续滚动；paged = 左右翻页。
  String readerMode = 'scroll';

  /// 音量键翻页（Android，翻页模式/滚动模式都可用）。
  bool readerVolumeKeys = false;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    await shelfUpdateSchedule.load();
    await updateNotifications.load();
    await readingStats.load();
    _restoreSearchHistory(sp.get(_kSearchHistory));
    final filterData = sp.get(_kSearchFilters);
    try {
      _searchFilters = SearchFilters.fromJson(
        filterData is String ? jsonDecode(filterData) : null,
      );
    } on FormatException {
      _searchFilters = SearchFilters();
    }
    _shelfSort = ShelfSort.parse(sp.get(_kShelfSort));
    sources
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kSources) ?? '[]') as List)
            .whereType<Map<String, dynamic>>()
            .map(ComicSource.fromJson),
      );
    repos
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kRepos) ?? '[]') as List).cast<String>(),
      );
    shelf
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kShelf) ?? '[]') as List)
            .whereType<Map<String, dynamic>>()
            .map(Book.fromJson),
      );
    await shelfGroups.load(shelf.map((book) => book.bookUrl));
    progress
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kProgress) ?? '{}') as Map<String, dynamic>)
            .map(
              (k, v) => MapEntry(
                k,
                ReadingProgress.fromJson(v as Map<String, dynamic>),
              ),
            ),
      );
    detailCache
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kDetailCache) ?? '{}')
                as Map<String, dynamic>)
            .map(
              (k, v) =>
                  MapEntry(k, CachedDetail.fromJson(v as Map<String, dynamic>)),
            ),
      );
    _restoreShelfUpdates(sp);
    repoLastRefresh
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kRepoRefresh) ?? '{}')
                as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int)),
      );
    repoUpdates
      ..clear()
      ..addAll(
        (jsonDecode(sp.getString(_kRepoUpdates) ?? '{}')
                as Map<String, dynamic>)
            .map(
              (k, v) => MapEntry(
                k,
                RepoUpdateState.fromJson(v as Map<String, dynamic>),
              ),
            ),
      );
    final adText = sp.getString(_kAdBlock);
    adBlock = adText == null ? null : AdBlockRules.tryParse(adText);
    SourceService.instance.adBlock = adBlock;
    _restoreDomainBlocklist(sp.get(_kDomainBlocklist));
    final wd = sp.getString(_kWebDav);
    webDavConfig = wd == null
        ? null
        : (jsonDecode(wd) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v.toString()),
          );
    darkMode = sp.getBool(_kDark) ?? true;
    readerBrightness = sp.getDouble(_kReaderBrightness) ?? 1.0;
    scrollOffsets.clear();
    final offs = sp.getString(_kScrollOffsets);
    if (offs != null) {
      try {
        final saved = jsonDecode(offs);
        if (saved is Map<String, dynamic>) {
          saved.forEach((k, v) {
            if (v is! Map<String, dynamic> ||
                v['v'] is! num ||
                v['at'] is! int) {
              return;
            }
            final offset = (v['v'] as num).toDouble();
            if (!offset.isFinite || offset < 0) return;
            final width = v['w'];
            final top = v['top'];
            scrollOffsets[k] = (
              offset: offset,
              at: v['at'] as int,
              width: width is num && width.isFinite && width > 0
                  ? width.toDouble()
                  : null,
              topInset: top is num && top.isFinite && top >= 0
                  ? top.toDouble()
                  : 0,
            );
          });
        }
      } on FormatException {
        scrollOffsets.clear();
      }
    }
    _lastAutoProbeAt = sp.getInt(_kLastAutoProbe) ?? 0;
    readerMode = sp.getString(_kReaderMode) == 'paged' ? 'paged' : 'scroll';
    readerVolumeKeys = sp.getBool(_kReaderVolumeKeys) ?? false;
    _restoreReaderPages(sp.get(_kReaderPages));
    // 首次启动自动导入内置源快照
    if (sources.isEmpty) {
      await importBuiltinSources();
    } else if (sources.any(
      (s) =>
          (s.rules.searchUrl.isEmpty && s.rules.searchList.isNotEmpty) ||
          s.rules.chapterUrl.isNotEmpty,
    )) {
      // 旧版曾漏映射 ruleSearchUrl、错误覆盖 chapterUrl；搜索正常也需检查目录。
      // 升级只修复已有内置源，不重新添加用户删掉的源。
      await _importBuiltinSources(addMissing: false);
    }
    await downloads.load();
    _restoreReadingHistory(sp.get(_kReadingHistory));
    if (!sp.containsKey(_kReadingHistory)) await _persistReadingHistory();
    _restoreChapterBookmarks(sp.get(_kChapterBookmarks));
  }

  void _restoreSearchHistory(Object? saved) {
    _searchHistory.clear();
    if (saved is! String) return;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) return;
      _searchHistory.addAll(
        decoded
            .whereType<String>()
            .map((query) => query.trim())
            .where((query) => query.isNotEmpty)
            .toSet()
            .take(_searchHistoryLimit),
      );
    } on FormatException {
      // 历史损坏时从空列表恢复，不影响启动。
    }
  }

  /// 仅在提交搜索时记录；再次搜索已有词会移到最前。
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchHistory
      ..remove(trimmed)
      ..insert(0, trimmed);
    if (_searchHistory.length > _searchHistoryLimit) {
      _searchHistory.removeRange(_searchHistoryLimit, _searchHistory.length);
    }
    await _persistSearchHistory();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory.clear();
    await _persistSearchHistory();
  }

  Future<void> setSearchFilters(SearchFilters filters) async {
    if (_searchFilters == filters) return;
    _searchFilters = filters;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kSearchFilters,
      jsonEncode(_searchFilters.toJson()),
    );
  }

  Future<void> setShelfSort(ShelfSort sort) async {
    if (_shelfSort == sort) return;
    _shelfSort = sort;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kShelfSort, _shelfSort.id);
  }

  /// 分组、连载状态和本地搜索之后，再按当前排序偏好排列。
  List<Book> shelfBooks({String query = '', int kindFilter = 0}) =>
      visibleShelfBooks(
        shelf,
        matchesGroup: (book) => shelfGroups.matches(book.bookUrl),
        query: query,
        kindFilter: kindFilter,
        sort: _shelfSort,
        readAt: (book) => progress[book.bookUrl]?.at ?? 0,
        catalogAt: (book) => detailCacheFor(book.bookUrl)?.at ?? 0,
      );

  Future<void> _persistSearchHistory() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kSearchHistory, jsonEncode(_searchHistory));
    notifyListeners();
  }

  /// 记录阅读进度（打开章节时调用；同一本书只保留最新）。
  Future<void> saveProgress(
    Book book, {
    required String chapterUrl,
    required String chapterTitle,
    required int chapterIndex,
    required int chapterCount,
  }) async {
    final reading = ReadingProgress(
      bookUrl: book.bookUrl,
      sourceId: book.sourceId ?? '',
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    progress[book.bookUrl] = reading;
    _rememberReading(book, reading);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kProgress,
      jsonEncode(progress.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await _persistReadingHistory();
    notifyListeners();
  }

  ReadingProgress? progressFor(String bookUrl) => progress[bookUrl];

  Book _historyBook(ReadingProgress reading, {Book? preferred}) {
    final sourceId = reading.sourceId;
    final url = reading.bookUrl;
    final old = _readingHistory
        .where(
          (entry) =>
              entry.book.bookUrl == url &&
              (entry.book.sourceId ?? '') == sourceId,
        )
        .firstOrNull
        ?.book;
    final cached = detailCacheFor(url)?.book;
    final saved = shelf
        .where(
          (book) => book.bookUrl == url && (book.sourceId ?? '') == sourceId,
        )
        .firstOrNull;
    final base =
        old ?? saved ?? ((cached?.sourceId ?? '') == sourceId ? cached : null);
    final fresh = preferred ?? base ?? Book();
    return Book.fromJson({
      ...?base?.toJson(),
      ...fresh.toJson(),
      'bookUrl': url,
      'sourceId': sourceId,
      if (fresh.name.trim().isEmpty) 'name': base?.name ?? '未命名漫画',
    });
  }

  void _rememberReading(Book book, ReadingProgress reading) {
    if (reading.bookUrl.isEmpty) return;
    final entry = ReadingHistoryEntry(
      book: _historyBook(reading, preferred: book),
      chapter: Chapter(title: reading.chapterTitle, url: reading.chapterUrl),
      chapterIndex: reading.chapterIndex,
      chapterCount: reading.chapterCount,
      at: reading.at,
    );
    _readingHistory.removeWhere((old) => old.key == entry.key);
    final index = _readingHistory.indexWhere((old) => old.at <= entry.at);
    _readingHistory.insert(index < 0 ? _readingHistory.length : index, entry);
  }

  void _restoreReadingHistory(Object? saved) {
    _readingHistory.clear();
    if (saved == null) {
      // 首次升级只迁移一次；已移除的记录不会在下次启动时重新出现。
      final readings = progress.values.toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      for (final reading in readings) {
        _rememberReading(_historyBook(reading), reading);
      }
      return;
    }
    if (saved is! String) return;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) return;
      final entries = <(int, ReadingHistoryEntry)>[];
      for (final (index, value) in decoded.indexed) {
        try {
          if (value is! Map<String, dynamic>) continue;
          final entry = ReadingHistoryEntry.fromJson(value);
          if (entry.book.bookUrl.isEmpty ||
              entry.chapterIndex < 0 ||
              entry.chapterCount < 0 ||
              entry.at < 0) {
            continue;
          }
          entries.add((index, entry));
        } catch (_) {
          // 保留同一列表中其它完整记录。
        }
      }
      entries.sort((a, b) {
        final byTime = b.$2.at.compareTo(a.$2.at);
        return byTime == 0 ? a.$1.compareTo(b.$1) : byTime;
      });
      final seen = <String>{};
      _readingHistory.addAll(
        entries.map((entry) => entry.$2).where((entry) => seen.add(entry.key)),
      );
    } on FormatException {
      // 历史损坏不影响书架、阅读进度或应用启动。
    }
  }

  Future<void> _persistReadingHistory() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kReadingHistory,
      jsonEncode(_readingHistory.map((entry) => entry.toJson()).toList()),
    );
  }

  /// 仅从时间线移除，保留书架、章节进度和章内位置以便再次续读。
  Future<void> removeReadingHistory(String key) async {
    _readingHistory.removeWhere((entry) => entry.key == key);
    await _persistReadingHistory();
    notifyListeners();
  }

  List<ChapterBookmark> bookmarksFor(Book book) {
    final key = ChapterBookmark.bookKeyFor(book);
    return _chapterBookmarks.where((entry) => entry.bookKey == key).toList();
  }

  bool isChapterBookmarked(Book book, Chapter chapter) {
    if (chapter.url.isEmpty) return false;
    final key = ChapterBookmark.keyFor(book, chapter);
    return _chapterBookmarks.any((entry) => entry.key == key);
  }

  /// 添加或移除当前话书签。返回 true 表示现在已收藏。
  Future<bool> toggleChapterBookmark(
    Book book, {
    required Chapter chapter,
    required int chapterIndex,
  }) async {
    if (book.bookUrl.isEmpty || chapter.url.isEmpty || chapterIndex < 0) {
      return isChapterBookmarked(book, chapter);
    }
    final key = ChapterBookmark.keyFor(book, chapter);
    final existing = _chapterBookmarks.indexWhere((entry) => entry.key == key);
    if (existing >= 0) {
      _chapterBookmarks.removeAt(existing);
      await _persistChapterBookmarks();
      notifyListeners();
      return false;
    }
    final entry = ChapterBookmark(
      book: Book.fromJson(book.toJson()),
      chapter: Chapter.fromJson(chapter.toJson()),
      chapterIndex: chapterIndex,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _chapterBookmarks.insert(0, entry);
    await _persistChapterBookmarks();
    notifyListeners();
    return true;
  }

  /// 只移除书签，不影响阅读进度、历史或章内位置。
  Future<void> removeChapterBookmark(String key) async {
    final before = _chapterBookmarks.length;
    _chapterBookmarks.removeWhere((entry) => entry.key == key);
    if (_chapterBookmarks.length == before) return;
    await _persistChapterBookmarks();
    notifyListeners();
  }

  void _restoreChapterBookmarks(Object? saved) {
    _chapterBookmarks.clear();
    if (saved is! String) return;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) return;
      final entries = <(int, ChapterBookmark)>[];
      for (final (index, value) in decoded.indexed) {
        try {
          if (value is! Map<String, dynamic>) continue;
          final entry = ChapterBookmark.fromJson(value);
          if (entry.book.bookUrl.isEmpty ||
              entry.chapter.url.isEmpty ||
              entry.chapterIndex < 0 ||
              entry.at < 0) {
            continue;
          }
          entries.add((index, entry));
        } catch (_) {
          // 保留同一列表中其它完整记录。
        }
      }
      entries.sort((a, b) {
        final byTime = b.$2.at.compareTo(a.$2.at);
        return byTime == 0 ? a.$1.compareTo(b.$1) : byTime;
      });
      final seen = <String>{};
      _chapterBookmarks.addAll(
        entries.map((entry) => entry.$2).where((entry) => seen.add(entry.key)),
      );
    } on FormatException {
      // 书签损坏不影响书架、阅读进度或应用启动。
    }
  }

  Future<void> _persistChapterBookmarks() async {
    final token = ++_bookmarkWrite;
    final payload = jsonEncode(
      _chapterBookmarks.map((entry) => entry.toJson()).toList(),
    );
    final sp = await SharedPreferences.getInstance();
    if (_disposed || token != _bookmarkWrite) return;
    await sp.setStringSafe(_kChapterBookmarks, payload);
  }

  void _restoreShelfUpdates(SharedPreferences sp) {
    _shelfChapters.clear();
    _shelfDismissals.clear();
    try {
      final raw = sp.get(_kShelfChapters);
      final saved = raw is String ? jsonDecode(raw) : null;
      if (saved is Map<String, dynamic>) {
        for (final book in shelf) {
          try {
            final value = saved[book.bookUrl];
            if (value is Map<String, dynamic>) {
              _shelfChapters[book.bookUrl] = ShelfChapters.fromJson(value);
            }
          } catch (_) {
            // 单本记录损坏时仍可从详情缓存恢复。
          }
        }
      }
    } on FormatException {
      // 不影响书架和阅读进度恢复。
    }
    for (final book in shelf) {
      final cached = detailCache[book.bookUrl];
      if (!_shelfChapters.containsKey(book.bookUrl) &&
          cached != null &&
          cached.chapters.isNotEmpty &&
          cached.book.sourceId == book.sourceId) {
        _shelfChapters[book.bookUrl] = ShelfChapters.fromDetail(
          cached.book,
          cached.chapters,
        );
      }
    }
    try {
      final raw = sp.get(_kShelfDismissals);
      final saved = raw is String ? jsonDecode(raw) : null;
      if (saved is Map<String, dynamic>) {
        for (final book in shelf) {
          final value = saved[book.bookUrl];
          if (value is String) _shelfDismissals[book.bookUrl] = value;
        }
      }
    } on FormatException {
      // 损坏的清除记录只会重新显示角标。
    }
  }

  ShelfUpdateBadge? shelfUpdateFor(Book book, {bool includeDismissed = false}) {
    final saved = progressFor(book.bookUrl);
    final reading = saved?.sourceId == (book.sourceId ?? '') ? saved : null;
    final snapshot = _shelfChapters[book.bookUrl];
    final catalog = snapshot?.sourceId == (book.sourceId ?? '')
        ? snapshot
        : null;
    final latest = catalog?.latestTitle ?? book.lastChapter;
    final urls = catalog?.urls ?? const <String>[];
    final latestUrl = urls.isEmpty ? '' : urls.last;
    int? unread;
    if (urls.isNotEmpty) {
      final index = reading == null || reading.chapterUrl.isEmpty
          ? -1
          : urls.indexOf(reading.chapterUrl);
      if (reading == null || index >= 0) unread = urls.length - index - 1;
    }
    if (unread == 0) return null;
    if (unread == null) {
      if (normalizeChapterTitle(latest).isEmpty ||
          (reading != null &&
              normalizeChapterTitle(latest) ==
                  normalizeChapterTitle(reading.chapterTitle))) {
        return null;
      }
    }
    final token = shelfUpdateToken(book.sourceId ?? '', latestUrl, latest);
    if (!includeDismissed && _shelfDismissals[book.bookUrl] == token) {
      return null;
    }
    return ShelfUpdateBadge(
      token: token,
      unreadCount: unread,
      latestTitle: latest,
      label: unread != null ? '未读 $unread' : (reading == null ? '未读' : '更新'),
    );
  }

  /// 清除提醒不修改真实阅读进度；最新话变化后自动重新显示。
  Future<void> clearShelfUpdate(Book book) async {
    final badge = shelfUpdateFor(book, includeDismissed: true);
    if (badge == null) return;
    _shelfDismissals[book.bookUrl] = badge.token;
    await _persistShelfUpdates();
    notifyListeners();
  }

  Future<void> clearShelfUpdates() async {
    for (final book in shelf) {
      final badge = shelfUpdateFor(book, includeDismissed: true);
      if (badge != null) _shelfDismissals[book.bookUrl] = badge.token;
    }
    await _persistShelfUpdates();
    notifyListeners();
  }

  Future<void> _persistShelfUpdates() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kShelfChapters,
      jsonEncode(
        _shelfChapters.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    await sp.setStringSafe(_kShelfDismissals, jsonEncode(_shelfDismissals));
  }

  /// 手动/自动共用检查：并发最多 3 本，单本失败不覆盖上次成功的目录。
  Future<ShelfRefreshResult> refreshShelfUpdates() {
    final pending = _shelfRefresh;
    if (pending != null) return pending;
    final request = _refreshShelfUpdates().whenComplete(() {
      _shelfRefresh = null;
      if (!_disposed) notifyListeners();
    });
    _shelfRefresh = request;
    notifyListeners();
    return request;
  }

  Future<ShelfRefreshResult> _refreshShelfUpdates() async {
    var checked = 0;
    var failed = 0;
    var skipped = 0;
    final targets = List<Book>.of(shelf);
    final previousTokens = <String, String>{};
    final previouslyCataloged = <String>{};
    for (final book in targets) {
      final key = shelfUpdateNoticeKey(book);
      final badge = shelfUpdateFor(book);
      if (badge != null) previousTokens[key] = badge.token;
      if (_shelfChapters.containsKey(book.bookUrl)) {
        previouslyCataloged.add(key);
      }
    }
    await shelfUpdateSchedule.recordCheck();
    Future<void> refresh(Book book) async {
      if (_disposed) {
        skipped++;
        return;
      }
      final source = sources
          .where((s) => s.id == book.sourceId && s.enabled)
          .firstOrNull;
      if (source == null) {
        skipped++;
        return;
      }
      try {
        final (fresh, chapters) = await SourceService.instance
            .runtimeFor(source)
            .detail(book.bookUrl)
            .timeout(const Duration(seconds: 20));
        if (_disposed ||
            !inShelf(book) ||
            !sources.any((s) => identical(s, source) && s.enabled)) {
          skipped++;
          return;
        }
        if (chapters.isEmpty) throw StateError('未取得章节目录');
        await saveDetailCache(fresh, chapters);
        checked++;
      } catch (_) {
        failed++;
      }
    }

    for (var i = 0; i < targets.length; i += 3) {
      await Future.wait(targets.skip(i).take(3).map(refresh));
    }
    await _notifyShelfUpdates(
      previousTokens: previousTokens,
      previouslyCataloged: previouslyCataloged,
    );
    return (checked: checked, failed: failed, skipped: skipped);
  }

  Future<bool> setUpdateNotificationsEnabled(bool value) async {
    if (value) {
      final allowed = await updateNotifier.requestPermission();
      if (!allowed) return false;
    } else {
      await updateNotifier.cancelAll();
    }
    await updateNotifications.setEnabled(value);
    return true;
  }

  Book? shelfBookFor({required String bookUrl, required String sourceId}) {
    Book? byUrl;
    for (final book in shelf) {
      if (book.bookUrl != bookUrl) continue;
      if ((book.sourceId ?? '') == sourceId) return book;
      byUrl ??= book;
    }
    return byUrl;
  }

  Future<void> _notifyShelfUpdates({
    required Map<String, String> previousTokens,
    required Set<String> previouslyCataloged,
  }) async {
    if (_disposed || !updateNotifications.enabled) return;
    final notices = shelfUpdatesToNotify(
      shelf: shelf,
      previousTokens: previousTokens,
      previouslyCataloged: previouslyCataloged,
      notifiedTokens: updateNotifications.notifiedTokens,
      badgeFor: shelfUpdateFor,
    );
    for (final notice in notices) {
      if (_disposed || !updateNotifications.enabled) return;
      final shown = await updateNotifier.show(notice);
      if (shown && !_disposed) {
        await updateNotifications.markNotified(notice.key, notice.badge.token);
      }
    }
  }

  /// 记录章内滚动位置（LRU 上限 200；节流由调用方负责）。
  Future<void> saveScrollOffset(
    String chapterUrl,
    double offset, {
    double? viewportWidth,
    double topInset = 0,
  }) async {
    if (chapterUrl.isEmpty || !offset.isFinite) return;
    scrollOffsets[chapterUrl] = (
      offset: offset < 0 ? 0 : offset,
      at: DateTime.now().millisecondsSinceEpoch,
      width:
          viewportWidth != null && viewportWidth.isFinite && viewportWidth > 0
          ? viewportWidth
          : null,
      topInset: topInset.isFinite && topInset >= 0 ? topInset : 0,
    );
    while (scrollOffsets.length > 200) {
      String? oldest;
      int? oldestAt;
      scrollOffsets.forEach((k, v) {
        if (oldestAt == null || v.at < oldestAt!) {
          oldest = k;
          oldestAt = v.at;
        }
      });
      if (oldest == null) break;
      scrollOffsets.remove(oldest);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kScrollOffsets,
      jsonEncode(
        scrollOffsets.map(
          (k, v) => MapEntry(k, {
            'v': v.offset,
            'at': v.at,
            if (v.width != null) 'w': v.width,
            if (v.width != null && v.topInset != 0) 'top': v.topInset,
          }),
        ),
      ),
    );
  }

  double? scrollOffsetFor(
    String chapterUrl, {
    double? viewportWidth,
    double topInset = 0,
  }) {
    final saved = scrollOffsets[chapterUrl];
    if (saved == null) return null;
    if (viewportWidth == null || saved.width == null) return saved.offset;
    return resizeScrollOffset(
      offset: saved.offset,
      fromWidth: saved.width!,
      toWidth: viewportWidth,
      fromTopInset: saved.topInset,
      toTopInset: topInset,
    );
  }

  void _restoreReaderPages(Object? saved) {
    _readerPages.clear();
    if (saved is! String) return;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final page = entry.value;
        if (entry.key is String &&
            (entry.key as String).isNotEmpty &&
            page is int &&
            page >= 0) {
          _readerPages[entry.key as String] = page;
        }
      }
      _trimReaderPages();
    } on FormatException {
      // 页码损坏时从首图开始，不影响其它阅读进度。
    }
  }

  void _trimReaderPages() {
    while (_readerPages.length > 200) {
      _readerPages.remove(_readerPages.keys.first);
    }
  }

  /// 保存从 0 开始的章内页码；页数上限由阅读器取得图片列表后校正。
  Future<void> saveReaderPage(String chapterUrl, int page) async {
    if (chapterUrl.isEmpty || page < 0) return;
    _readerPages.remove(chapterUrl);
    _readerPages[chapterUrl] = page;
    _trimReaderPages();
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kReaderPages, jsonEncode(_readerPages));
  }

  int? readerPageFor(String chapterUrl) => _readerPages[chapterUrl];

  /// 章内翻页位置快照（备份用）。
  Map<String, int> get readerPages => Map.unmodifiable(_readerPages);

  /// 章节目录缓存（离线可见 + 秒开），成功拉取详情后调用；超上限按时间淘汰。
  Future<void> saveDetailCache(Book book, List<Chapter> chapters) async {
    if (book.bookUrl.isEmpty || chapters.isEmpty) return;
    detailCache[book.bookUrl] = CachedDetail(
      book: book,
      chapters: chapters,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    while (detailCache.length > _detailCacheCap) {
      String? oldest;
      int? oldestAt;
      detailCache.forEach((k, v) {
        if (oldestAt == null || v.at < oldestAt!) {
          oldest = k;
          oldestAt = v.at;
        }
      });
      if (oldest == null) break;
      detailCache.remove(oldest);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kDetailCache,
      jsonEncode(detailCache.map((k, v) => MapEntry(k, v.toJson()))),
    );
    final index = shelf.indexWhere(
      (b) => b.bookUrl == book.bookUrl && b.sourceId == book.sourceId,
    );
    if (index >= 0) {
      shelf[index] = Book.fromJson({
        ...shelf[index].toJson(),
        ...book.toJson(),
        if (book.name.trim().isEmpty) 'name': shelf[index].name,
      });
      _shelfChapters[book.bookUrl] = ShelfChapters.fromDetail(book, chapters);
      await sp.setStringSafe(
        _kShelf,
        jsonEncode(shelf.map((b) => b.toJson()).toList()),
      );
      await _persistShelfUpdates();
      if (!_disposed) notifyListeners();
    }
  }

  CachedDetail? detailCacheFor(String bookUrl) {
    final cached = detailCache[bookUrl];
    if (cached != null) return cached;
    final offline = downloads.offlineCatalogFor(bookUrl);
    return offline == null
        ? null
        : CachedDetail(
            book: offline.book,
            chapters: offline.chapters,
            at: offline.at,
          );
  }

  /// 检查一个订阅仓库的更新：重新拉取 store，规则有变则就地更新（保留
  /// 启用/权重/健康），新增源直接追加。[client] 可注入（测试用）。
  Future<RepoRefreshResult> refreshRepo(
    String repoUrl, {
    RepoClient? client,
  }) async {
    final c = client ?? SourceService.instance.repoClient;
    try {
      final bundle = await c.subscribe(repoUrl);
      final r = SourceUpdate.merge(sources, bundle.sources);
      sources
        ..clear()
        ..addAll(r.sources);
      repoLastRefresh[repoUrl] = DateTime.now().millisecondsSinceEpoch;
      _recordRepoVersion(
        repoUrl,
        bundle.meta.ruleVersion,
        metaAuto: bundle.meta.ruleAuto,
      );
      await _persistRepoMeta();
      await _persistSources();
      notifyListeners();
      return RepoRefreshResult(
        repo: repoUrl,
        added: r.added,
        updated: r.updated,
        total: bundle.sources.length,
        track: bundle.track,
      );
    } catch (e) {
      final msg = e.toString().split('\n').first;
      return RepoRefreshResult(
        repo: repoUrl,
        added: 0,
        updated: 0,
        total: 0,
        error: msg,
      );
    }
  }

  /// 逐个检查全部订阅仓库。
  Future<List<RepoRefreshResult>> refreshAllRepos({RepoClient? client}) async {
    final out = <RepoRefreshResult>[];
    for (final repo in repos) {
      out.add(await refreshRepo(repo, client: client));
    }
    return out;
  }

  void _recordRepoVersion(String repoUrl, int ruleVersion, {bool? metaAuto}) {
    final st = repoUpdates[repoUrl] ?? RepoUpdateState();
    repoUpdates[repoUrl] = RepoUpdateState(
      lastRuleVersion: ruleVersion,
      pendingVersion: -1,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
      auto: metaAuto ?? st.auto,
    );
  }

  Future<void> _persistRepoMeta() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kRepoRefresh, jsonEncode(repoLastRefresh));
    await sp.setStringSafe(
      _kRepoUpdates,
      jsonEncode(repoUpdates.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 轻量版本检查：只拉各仓库 meta（不拉全量 store），比对 ruleVersion。
  /// 新版本 → 标记 pending（meta.ruleAuto 时立即自动应用）。
  /// 仓库无版本号（ruleVersion=0）时退化为全量刷新比对。
  Future<List<String>> checkRepoUpdates({RepoClient? client}) async {
    final c = client ?? SourceService.instance.repoClient;
    final notices = <String>[];
    for (final repoUrl in repos) {
      try {
        final meta = await c.fetchMeta(repoUrl);
        final st = repoUpdates[repoUrl] ?? RepoUpdateState();
        final checkedAt = DateTime.now().millisecondsSinceEpoch;
        if (meta.ruleVersion > 0 &&
            st.lastRuleVersion >= 0 &&
            meta.ruleVersion > st.lastRuleVersion) {
          // 有新版本
          repoUpdates[repoUrl] = RepoUpdateState(
            lastRuleVersion: st.lastRuleVersion,
            pendingVersion: meta.ruleVersion,
            checkedAt: checkedAt,
            auto: meta.ruleAuto,
          );
          if (meta.ruleAuto) {
            await refreshRepo(repoUrl, client: c);
            notices.add('$repoUrl：已自动更新到 v${meta.ruleVersion}');
          } else {
            notices.add('$repoUrl：发现新版本 v${meta.ruleVersion}');
          }
        } else if (meta.ruleVersion == 0) {
          // 仓库无版本号：退化为全量刷新做内容比对
          final r = await refreshRepo(repoUrl, client: c);
          if (r.ok && (r.added > 0 || r.updated > 0)) {
            notices.add('$repoUrl：源有变更（新增 ${r.added} · 更新 ${r.updated}）');
          }
        } else {
          repoUpdates[repoUrl] = RepoUpdateState(
            lastRuleVersion: st.lastRuleVersion,
            pendingVersion: st.pendingVersion,
            checkedAt: checkedAt,
            auto: meta.ruleAuto,
          );
        }
      } catch (e) {
        // 检查失败不打断其他仓库
        continue;
      }
    }
    if (repoUpdates.isNotEmpty || repoLastRefresh.isNotEmpty) {
      await _persistRepoMeta();
      notifyListeners();
    }
    return notices;
  }

  /// 启动自动检查（节流：距上次检查不足 [_autoCheckIntervalMs] 则跳过）。
  /// 静默执行，结果通过 repoUpdates/notifyListeners 反映。
  Future<void> autoCheckUpdates({RepoClient? client}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = repos.any((r) {
      final st = repoUpdates[r];
      return st == null || now - st.checkedAt > _autoCheckIntervalMs;
    });
    if (!due) return;
    await checkRepoUpdates(client: client);
  }

  /// 应用一个仓库的待更新版本（等价全量刷新）。
  Future<RepoRefreshResult> applyRepoUpdate(
    String repoUrl, {
    RepoClient? client,
  }) => refreshRepo(repoUrl, client: client);

  /// 合并备份载荷：源按 id 替换（备份优先）、书架并集、进度取较新、
  /// 订阅仓库并集。单次持久化 + 单次通知。
  Future<BackupImportCounts> mergeBackup({
    required List<ComicSource> sources,
    required List<Book> shelf,
    required Map<String, ReadingProgress> progress,
    required List<String> repos,
  }) {
    return applyBackup(
      BackupPayload(
        version: 1,
        sources: sources,
        shelf: shelf,
        progress: progress,
        repos: repos,
      ),
    );
  }

  /// 应用备份。[mode] 为覆盖时先清空对应集合；缺省的历史/书签/设置保持本地。
  Future<BackupImportCounts> applyBackup(
    BackupPayload payload, {
    BackupImportMode mode = BackupImportMode.merge,
  }) async {
    final overwrite = mode == BackupImportMode.overwrite;
    if (overwrite) {
      sources.clear();
      shelf.clear();
      progress.clear();
      repos.clear();
      if (payload.history != null) _readingHistory.clear();
      if (payload.bookmarks != null) _chapterBookmarks.clear();
      if (payload.readerPages != null) _readerPages.clear();
      if (payload.scrollOffsets != null) scrollOffsets.clear();
    }

    var nSrc = 0, nShelf = 0, nProg = 0, nRepo = 0;
    for (final s in payload.sources) {
      final idx = sources.indexWhere((e) => e.id == s.id);
      if (idx < 0) {
        sources.add(s);
        nSrc++;
      } else if (overwrite ||
          SourceUpdate.fingerprint(sources[idx]) !=
              SourceUpdate.fingerprint(s)) {
        if (!overwrite) {
          // 合并时保留本地启用/权重/健康，规则以备份为准
          s.enabled = sources[idx].enabled;
          s.weight = sources[idx].weight;
          s.failCount = sources[idx].failCount;
          s.lastError = sources[idx].lastError;
          s.lastFailedAt = sources[idx].lastFailedAt;
          s.lastOkAt = sources[idx].lastOkAt;
        }
        sources[idx] = s;
        nSrc++;
      }
    }
    for (final b in payload.shelf) {
      final idx = shelf.indexWhere((e) => e.bookUrl == b.bookUrl);
      if (idx < 0) {
        shelf.add(b);
        nShelf++;
      } else if (overwrite) {
        shelf[idx] = b;
        nShelf++;
      }
    }
    final rememberFromProgress = payload.history == null;
    payload.progress.forEach((k, v) {
      final cur = progress[k];
      if (overwrite || cur == null || v.at > cur.at) {
        progress[k] = v;
        if (rememberFromProgress) _rememberReading(_historyBook(v), v);
        nProg++;
      }
    });
    for (final r in payload.repos) {
      if (!repos.contains(r)) {
        repos.add(r);
        nRepo++;
      }
    }

    var nHist = 0;
    if (payload.history != null) {
      for (final entry in payload.history!) {
        final idx = _readingHistory.indexWhere((old) => old.key == entry.key);
        if (idx < 0) {
          _rememberImportedHistory(entry);
          nHist++;
        } else if (overwrite || entry.at > _readingHistory[idx].at) {
          _readingHistory.removeAt(idx);
          _rememberImportedHistory(entry);
          nHist++;
        }
      }
    }

    var nMarks = 0;
    if (payload.bookmarks != null) {
      for (final entry in payload.bookmarks!) {
        final idx = _chapterBookmarks.indexWhere((old) => old.key == entry.key);
        if (idx < 0) {
          _chapterBookmarks.add(entry);
          nMarks++;
        } else if (overwrite || entry.at > _chapterBookmarks[idx].at) {
          _chapterBookmarks[idx] = entry;
          nMarks++;
        }
      }
      _chapterBookmarks.sort((a, b) {
        final byTime = b.at.compareTo(a.at);
        return byTime == 0 ? a.key.compareTo(b.key) : byTime;
      });
    }

    var nSettings = 0;
    nSettings += await _applyBackupSettings(
      payload.settings,
      overwrite: overwrite,
    );
    if (payload.shelfGroups != null) {
      nSettings += await shelfGroups.importBackup(
        payload.shelfGroups!,
        bookUrls: shelf.map((book) => book.bookUrl),
        overwrite: overwrite,
      );
    } else if (overwrite) {
      final urls = shelf.map((book) => book.bookUrl).toSet();
      for (final url in shelfGroups.assignedBookUrls.toList()) {
        if (!urls.contains(url)) await shelfGroups.removeBook(url);
      }
    }
    if (payload.readingStats != null) {
      nSettings += await readingStats.importBackup(
        payload.readingStats!,
        overwrite: overwrite,
      );
    }
    if (payload.readerPages != null) {
      payload.readerPages!.forEach((key, page) {
        _readerPages[key] = page;
        nSettings++;
      });
      _trimReaderPages();
    }
    if (payload.scrollOffsets != null) {
      _restoreScrollOffsets(payload.scrollOffsets, merge: !overwrite);
      nSettings += payload.scrollOffsets!.length;
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kSources,
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
    await sp.setStringSafe(
      _kShelf,
      jsonEncode(shelf.map((e) => e.toJson()).toList()),
    );
    await sp.setStringSafe(
      _kProgress,
      jsonEncode(progress.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await sp.setStringSafe(_kRepos, jsonEncode(repos));
    await _persistReadingHistory();
    await _persistChapterBookmarks();
    await _persistShelfUpdates();
    await sp.setStringSafe(_kSearchHistory, jsonEncode(_searchHistory));
    await sp.setStringSafe(
      _kSearchFilters,
      jsonEncode(_searchFilters.toJson()),
    );
    await sp.setStringSafe(_kShelfSort, _shelfSort.id);
    await sp.setStringSafe(_kReaderPages, jsonEncode(_readerPages));
    await _persistScrollOffsets();
    notifyListeners();
    return (
      sources: nSrc,
      shelf: nShelf,
      progress: nProg,
      repos: nRepo,
      history: nHist,
      bookmarks: nMarks,
      settings: nSettings,
    );
  }

  void _rememberImportedHistory(ReadingHistoryEntry entry) {
    final index = _readingHistory.indexWhere((old) => old.at <= entry.at);
    _readingHistory.insert(index < 0 ? _readingHistory.length : index, entry);
  }

  Future<int> _applyBackupSettings(
    Map<String, dynamic>? settings, {
    required bool overwrite,
  }) async {
    if (settings == null) return 0;
    var n = 0;
    final sp = await SharedPreferences.getInstance();
    if (settings.containsKey('darkMode')) {
      darkMode = settings['darkMode'] == true;
      await sp.setBoolSafe(_kDark, darkMode);
      n++;
    }
    if (settings['readerBrightness'] is num) {
      readerBrightness = (settings['readerBrightness'] as num).toDouble().clamp(
        0.15,
        1.0,
      );
      await sp.setDoubleSafe(_kReaderBrightness, readerBrightness);
      n++;
    }
    if (settings['readerMode'] is String) {
      readerMode = settings['readerMode'] == 'paged' ? 'paged' : 'scroll';
      await sp.setStringSafe(_kReaderMode, readerMode);
      n++;
    }
    if (settings.containsKey('readerVolumeKeys')) {
      readerVolumeKeys = settings['readerVolumeKeys'] == true;
      await sp.setBoolSafe(_kReaderVolumeKeys, readerVolumeKeys);
      n++;
    }
    if (settings['shelfSort'] is String) {
      _shelfSort = ShelfSort.parse(settings['shelfSort']);
      await sp.setStringSafe(_kShelfSort, _shelfSort.id);
      n++;
    }
    if (await shelfUpdateSchedule.importBackup({
      if (settings.containsKey('shelfUpdateEnabled'))
        'enabled': settings['shelfUpdateEnabled'],
      if (settings.containsKey('shelfUpdateIntervalHours'))
        'intervalHours': settings['shelfUpdateIntervalHours'],
    })) {
      n++;
    }
    if (settings.containsKey('updateNotificationsEnabled')) {
      await updateNotifications.setEnabled(
        settings['updateNotificationsEnabled'] == true,
      );
      n++;
    }
    if (settings.containsKey('adBlock')) {
      final raw = settings['adBlock'];
      if (raw == null) {
        await setAdBlock(null);
        n++;
      } else {
        final text = raw is String ? raw : jsonEncode(raw);
        if (await setAdBlock(text)) n++;
      }
    }
    if (settings['blockedDomains'] is List) {
      final hosts = (settings['blockedDomains'] as List).whereType<String>();
      if (overwrite) {
        SourceService.instance.networkPolicy.replaceAll(hosts);
      } else {
        for (final host in hosts) {
          SourceService.instance.networkPolicy.add(host);
        }
      }
      await _persistDomainBlocklist();
      n++;
    }
    if (settings['searchFilters'] != null) {
      try {
        _searchFilters = SearchFilters.fromJson(settings['searchFilters']);
        n++;
      } on FormatException {
        // 保留本地筛选。
      }
    }
    if (settings['searchHistory'] is List) {
      final incoming = (settings['searchHistory'] as List)
          .whereType<String>()
          .map((query) => query.trim())
          .where((query) => query.isNotEmpty);
      if (overwrite) _searchHistory.clear();
      for (final query in incoming.toList().reversed) {
        _searchHistory
          ..remove(query)
          ..insert(0, query);
      }
      if (_searchHistory.length > _searchHistoryLimit) {
        _searchHistory.removeRange(_searchHistoryLimit, _searchHistory.length);
      }
      n++;
    }
    return n;
  }

  void _restoreScrollOffsets(
    Map<String, dynamic>? saved, {
    bool merge = false,
  }) {
    if (saved == null) return;
    if (!merge) scrollOffsets.clear();
    saved.forEach((k, v) {
      if (v is! Map<String, dynamic> || v['v'] is! num || v['at'] is! int) {
        return;
      }
      final offset = (v['v'] as num).toDouble();
      if (!offset.isFinite || offset < 0) return;
      final current = scrollOffsets[k];
      if (merge && current != null && current.at >= (v['at'] as int)) return;
      final width = v['w'];
      final top = v['top'];
      scrollOffsets[k] = (
        offset: offset,
        at: v['at'] as int,
        width: width is num && width.isFinite && width > 0
            ? width.toDouble()
            : null,
        topInset: top is num && top.isFinite && top >= 0 ? top.toDouble() : 0,
      );
    });
  }

  Future<void> _persistScrollOffsets() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kScrollOffsets,
      jsonEncode(
        scrollOffsets.map(
          (k, v) => MapEntry(k, {
            'v': v.offset,
            'at': v.at,
            if (v.width != null) 'w': v.width,
            if (v.width != null && v.topInset != 0) 'top': v.topInset,
          }),
        ),
      ),
    );
  }

  /// 待更新仓库数（角标用）。
  int get pendingUpdateCount =>
      repoUpdates.values.where((s) => s.hasPending).length;

  /// 轻量自动体检：只在距上次超过 [interval] 时跑，最多探 [maxSources] 个
  /// 启用源——优先从未探测过的开始（lastOkAt=0），其次上次探测最早的。
  /// 静默执行（结果写入健康记录，源页可看标红）。
  Future<void> autoProbeIfNeeded({
    int maxSources = 20,
    Duration interval = const Duration(days: 7),
    SourceRuntime Function(ComicSource source)? runtimeBuilder,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAutoProbeAt < interval.inMilliseconds) return;
    _lastAutoProbeAt = now;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastAutoProbe, now);

    // 排序：从未探测（无成败记录）最优先，其次上次成功最早
    int rank(ComicSource s) =>
        (s.lastOkAt == 0 && s.lastFailedAt == 0) ? -1 : s.lastOkAt;
    final candidates =
        sources.where((s) => s.enabled && s.rules.searchUrl.isNotEmpty).toList()
          ..sort((a, b) => rank(a).compareTo(rank(b)));
    final targets = candidates.take(maxSources).toList();
    if (targets.isEmpty) return;

    final builder =
        runtimeBuilder ?? (s) => SourceService.instance.runtimeFor(s);
    final okIds = <String>[];
    final errors = <String, String>{};
    for (var i = 0; i < targets.length; i += 8) {
      await Future.wait(
        targets.skip(i).take(8).map((s) async {
          try {
            await builder(
              s,
            ).search('斗罗大陆').timeout(const Duration(seconds: 10));
            okIds.add(s.id);
          } catch (e) {
            errors[s.id] = e.toString();
          }
        }),
      );
    }
    await reportSourceHealth(okIds, errors, observedSources: targets);
  }

  /// 源健康体检：对全部启用源做一次真实搜索探测（受限并发 + 单源超时），
  /// 结果走 [reportSourceHealth]（成功清零失败计数，失败累加→标红）。
  /// [runtimeBuilder] 可注入（测试用）。返回 (可用数, 总数)。
  Future<(int ok, int total)> probeSources({
    String keyword = '斗罗大陆',
    int concurrency = 8,
    Duration timeout = const Duration(seconds: 12),
    SourceRuntime Function(ComicSource source)? runtimeBuilder,
    void Function(int done, int total)? onProgress,
  }) async {
    final targets = sources
        .where((s) => s.enabled && s.rules.searchUrl.isNotEmpty)
        .toList();
    final builder =
        runtimeBuilder ?? (s) => SourceService.instance.runtimeFor(s);
    var done = 0;
    final okIds = <String>[];
    final errors = <String, String>{};

    Future<void> probeOne(ComicSource s) async {
      try {
        await builder(s).search(keyword).timeout(timeout);
        okIds.add(s.id);
      } catch (e) {
        errors[s.id] = e.toString();
      } finally {
        done++;
        onProgress?.call(done, targets.length);
      }
    }

    for (var i = 0; i < targets.length; i += concurrency) {
      await Future.wait(targets.skip(i).take(concurrency).map(probeOne));
    }
    await reportSourceHealth(okIds, errors, observedSources: targets);
    return (okIds.length, targets.length);
  }

  /// 导入 APK 内置的源快照（assets/store.json，493 条社区规则文本）。
  /// 按 id 去重：新源追加；修复缺失地址/请求头及已知错误章节链接，保留用户编辑。
  /// 返回新增 + 修复数量。
  Future<int> importBuiltinSources() => _importBuiltinSources(addMissing: true);

  Future<int> _importBuiltinSources({required bool addMissing}) async {
    final txt = await rootBundle.loadString('assets/store.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['sources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ComicSource.fromPpcatFlat);
    var added = 0;
    var repaired = 0;
    for (final s in list) {
      final idx = sources.indexWhere((e) => e.id == s.id);
      if (idx < 0) {
        if (addMissing) {
          sources.add(s);
          added++;
        }
        continue;
      }
      // 只增不删会让旧版映射丢掉的 searchUrl 永久空着；恢复时补回规则/请求头，
      // 保留启用/权重/健康记录（避免抹掉已知失效信息）。
      final existing = sources[idx];
      if (existing.url.isNotEmpty && existing.url != s.url) continue;
      final needsUrl = existing.url.isEmpty && s.url.isNotEmpty;
      final needsSearchUrl =
          existing.rules.searchUrl.isEmpty && s.rules.searchUrl.isNotEmpty;
      final needsHeaders = existing.headers.isEmpty && s.headers.isNotEmpty;
      // 仅替换与旧版错误映射完全相同的值，用户自行编辑的章节链接保持原样。
      final legacyChapterUrl = s.raw['ruleChapterUrl'];
      final needsChapterUrl =
          legacyChapterUrl is String &&
          legacyChapterUrl.isNotEmpty &&
          s.rules.chapterUrl.isNotEmpty &&
          legacyChapterUrl != s.rules.chapterUrl &&
          existing.rules.chapterUrl == legacyChapterUrl;
      if (needsUrl || needsSearchUrl || needsHeaders || needsChapterUrl) {
        // 替换对象以刷新运行时缓存，但不覆盖已有列表规则、名称等用户编辑。
        sources[idx] = ComicSource.fromJson({
          ...existing.toJson(),
          if (needsUrl) 'url': s.url,
          if (needsUrl || needsSearchUrl || needsChapterUrl)
            'rules': {
              if (needsUrl || needsSearchUrl) ...s.rules.toJson(),
              ...existing.rules.toJson(),
              if (needsChapterUrl) 'chapterUrl': s.rules.chapterUrl,
            },
          if (needsHeaders) 'headers': s.headers,
        });
        repaired++;
      }
    }
    if (added > 0 || repaired > 0) {
      await _persistSources();
      notifyListeners();
    }
    return added + repaired;
  }

  /// 批量回报源健康：[okIds] 本轮成功的源；[errors] 失败 {源id: 错误摘要}。
  /// 成功清零连续失败计数；失败累加并记原因/时间。一次持久化 + 一次通知。
  /// [observedSources] 是发起请求时的源对象，规则更新后忽略旧定义的回报。
  Future<void> reportSourceHealth(
    Iterable<String> okIds,
    Map<String, String> errors, {
    Iterable<ComicSource>? observedSources,
  }) async {
    final observed = observedSources == null
        ? null
        : {for (final source in observedSources) source.id: source};
    ComicSource? current(String id) {
      final source = _find(id);
      return observed == null || identical(source, observed[id])
          ? source
          : null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final id in okIds) {
      final s = current(id);
      if (s == null) continue;
      if (s.failCount != 0 || s.lastError.isNotEmpty || s.lastOkAt != now) {
        changed = true;
      }
      s.failCount = 0;
      s.lastError = '';
      s.lastOkAt = now;
    }
    errors.forEach((id, err) {
      final s = current(id);
      if (s == null) return;
      final msg = err.length > 120 ? err.substring(0, 120) : err;
      // 即使错误文案相同，连续失败次数和探测时间也需要落盘并刷新界面。
      changed = true;
      s.lastError = msg;
      s.lastFailedAt = now;
      s.failCount++;
    });
    if (changed) {
      await _persistSources();
      notifyListeners();
    }
  }

  /// 一键禁用失效候选（连续失败 ≥3 的启用源）。返回禁用数量。
  Future<int> disableUnhealthySources() async {
    var n = 0;
    for (final s in sources) {
      if (s.enabled && s.isUnhealthy) {
        s.enabled = false;
        n++;
      }
    }
    if (n > 0) {
      await _persistSources();
      notifyListeners();
    }
    return n;
  }

  /// 清空全部失败记录（重新探活时用）。
  Future<int> resetSourceHealth() async {
    var n = 0;
    for (final s in sources) {
      if (s.failCount != 0 || s.lastError.isNotEmpty || s.lastFailedAt != 0) {
        s.failCount = 0;
        s.lastError = '';
        s.lastFailedAt = 0;
        n++;
      }
    }
    if (n > 0) {
      await _persistSources();
      notifyListeners();
    }
    return n;
  }

  ComicSource? _find(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _persistSources() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kSources,
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> addRepoSubscribed(
    String repoUrl,
    List<ComicSource> imported,
  ) async {
    if (!repos.contains(repoUrl)) repos.add(repoUrl);
    for (final s in imported) {
      sources.removeWhere((e) => e.id == s.id);
      sources.add(s);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kRepos, jsonEncode(repos));
    await _persistSources();
    notifyListeners();
  }

  Future<void> addSourceManual(ComicSource s) async {
    sources.removeWhere((e) => e.id == s.id);
    sources.add(s);
    await _persistSources();
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    sources.removeWhere((e) => e.id == id);
    await _persistSources();
    notifyListeners();
  }

  Future<void> toggleSource(String id) async {
    for (final s in sources) {
      if (s.id == id) s.enabled = !s.enabled;
    }
    await _persistSources();
    notifyListeners();
  }

  Future<void> toggleShelf(Book b) async {
    final exists = shelf.any((e) => e.bookUrl == b.bookUrl);
    if (exists) {
      shelf.removeWhere((e) => e.bookUrl == b.bookUrl);
      _shelfChapters.remove(b.bookUrl);
      _shelfDismissals.remove(b.bookUrl);
      await shelfGroups.removeBook(b.bookUrl);
    } else {
      shelf.insert(0, b);
      final cached = detailCacheFor(b.bookUrl);
      if (cached != null &&
          cached.chapters.isNotEmpty &&
          cached.book.sourceId == b.sourceId) {
        _shelfChapters[b.bookUrl] = ShelfChapters.fromDetail(
          cached.book,
          cached.chapters,
        );
      }
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kShelf,
      jsonEncode(shelf.map((e) => e.toJson()).toList()),
    );
    await _persistShelfUpdates();
    notifyListeners();
  }

  bool inShelf(Book b) => shelf.any((e) => e.bookUrl == b.bookUrl);

  Future<void> assignShelfGroups(Book book, Iterable<String> groupIds) async {
    if (inShelf(book)) await shelfGroups.assign(book.bookUrl, groupIds);
  }

  Future<void> setDark(bool v) async {
    darkMode = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBoolSafe(_kDark, v);
    notifyListeners();
  }

  /// 阅读器亮度（遮罩式调暗，持久化全局）。
  Future<void> setReaderBrightness(double v) async {
    readerBrightness = v.clamp(0.15, 1.0);
    final sp = await SharedPreferences.getInstance();
    await sp.setDoubleSafe(_kReaderBrightness, readerBrightness);
    notifyListeners();
  }

  /// 阅读模式：scroll / paged。
  Future<void> setReaderMode(String mode) async {
    readerMode = mode == 'paged' ? 'paged' : 'scroll';
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(_kReaderMode, readerMode);
    notifyListeners();
  }

  /// 音量键翻页开关。
  Future<void> setReaderVolumeKeys(bool v) async {
    readerVolumeKeys = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBoolSafe(_kReaderVolumeKeys, v);
    notifyListeners();
  }

  /// 保存 WebDAV 配置（null 清除）。
  Future<void> setWebDavConfig(Map<String, String>? cfg) async {
    webDavConfig = cfg;
    final sp = await SharedPreferences.getInstance();
    if (cfg == null) {
      await sp.removeSafe(_kWebDav);
    } else {
      await sp.setStringSafe(_kWebDav, jsonEncode(cfg));
    }
    notifyListeners();
  }

  void _restoreDomainBlocklist(Object? saved) {
    var hosts = const <String>[];
    if (saved is String && saved.isNotEmpty) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is List) {
          hosts = decoded.whereType<String>().toList();
        }
      } on FormatException {
        hosts = const [];
      }
    }
    SourceService.instance.networkPolicy.replaceAll(hosts);
  }

  Future<void> _persistDomainBlocklist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringSafe(
      _kDomainBlocklist,
      jsonEncode(SourceService.instance.networkPolicy.hosts),
    );
  }

  /// 加入一条域名/URL；非法或重复返回 false。
  Future<bool> addBlockedDomain(String raw) async {
    if (!SourceService.instance.networkPolicy.add(raw)) return false;
    await _persistDomainBlocklist();
    notifyListeners();
    return true;
  }

  /// 移除一条；未命中返回 false。
  Future<bool> removeBlockedDomain(String raw) async {
    if (!SourceService.instance.networkPolicy.remove(raw)) return false;
    await _persistDomainBlocklist();
    notifyListeners();
    return true;
  }

  Future<void> setBlockedDomains(Iterable<String> domains) async {
    SourceService.instance.networkPolicy.replaceAll(domains);
    await _persistDomainBlocklist();
    notifyListeners();
  }

  /// 导入广告拦截规则 JSON（坏 JSON 返回 false）；text 为 null/空则清除。
  Future<bool> setAdBlock(String? text) async {
    final sp = await SharedPreferences.getInstance();
    if (text == null || text.trim().isEmpty) {
      adBlock = null;
      SourceService.instance.adBlock = null;
      await sp.removeSafe(_kAdBlock);
      notifyListeners();
      return true;
    }
    final rules = AdBlockRules.tryParse(text);
    if (rules == null) return false;
    adBlock = rules;
    SourceService.instance.adBlock = rules;
    await sp.setStringSafe(_kAdBlock, text);
    notifyListeners();
    return true;
  }
}
