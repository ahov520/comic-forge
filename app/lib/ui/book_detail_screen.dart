import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/source_share.dart';
import '../state/download_queue.dart';
import 'comic_reading_stats_screen.dart';
import 'chapter_bookmark_sheet.dart';
import 'detail_chrome.dart';
import 'download_selection_sheet.dart';
import 'downloads_screen.dart';
import 'skeleton.dart';
import 'source_screen.dart';
import 'widgets.dart';

/// 书籍详情 + 章节列表。
class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({
    super.key,
    required this.book,
    required this.appState,
    this.detailLoaderOverride,
    this.carryChapterIndex,
  });
  final Book book;
  final AppState appState;

  /// 详情加载器（测试接缝；null 用真实源运行时）。
  final Future<(Book, List<Chapter>)> Function(String bookUrl)?
  detailLoaderOverride;

  /// 换源迁移：以章序号对齐旧进度（皮皮喵语义，跨源章节名不一致按序号近似）。
  final int? carryChapterIndex;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Future<(Book, List<Chapter>)> _future;
  Book? _book;
  ComicSource? _source;
  int _detailGeneration = 0;
  bool _fromCache = false;
  bool _carryDone = false;
  bool _chaptersReversed = false;
  int? _switchCount; // 换源可命中数（后台预扫完成后显示角标）
  final _switchTargets = ValueNotifier<Future<List<(ComicSource, Book)>>?>(
    null,
  );

  /// 缓存命中时首帧直出的数据（避免 FutureBuilder 首帧闪骨架）。
  (Book, List<Chapter>)? _initialData;

  @override
  void initState() {
    super.initState();
    _load();
    widget.appState.addListener(_scanSwitchTargets);
    _scanSwitchTargets();
  }

  @override
  void didUpdateWidget(covariant BookDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_scanSwitchTargets);
      widget.appState.addListener(_scanSwitchTargets);
      _scanSwitchTargets();
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_scanSwitchTargets);
    _switchTargets.dispose();
    super.dispose();
  }

  /// 后台预扫换源目标（结果入 SourceService 缓存，面板复用；失败静默）。
  Future<void> _scanSwitchTargets({bool refresh = false}) async {
    try {
      final pending = SourceService.instance.scanSwitchTargets(
        book: widget.book,
        allSources: widget.appState.sources,
        useCache: !refresh,
      );
      if (identical(_switchTargets.value, pending)) return;
      _switchTargets.value = pending;
      if (_switchCount != null) setState(() => _switchCount = null);
      final result = await pending;
      if (mounted && identical(_switchTargets.value, pending)) {
        setState(() => _switchCount = result.length);
      }
    } catch (_) {
      // 静默：角标不显示也不影响换源面板（面板会再扫）
    }
  }

  void _load() {
    final generation = ++_detailGeneration;
    _book = null;
    _source = _findSource();
    final cached = widget.appState.detailCacheFor(widget.book.bookUrl);
    if (cached != null) {
      // stale-while-revalidate：先秒开缓存，再后台刷新（失败静默回退缓存）。
      // initialData 让 FutureBuilder 首帧即有数据——缓存命中不闪骨架。
      _fromCache = true;
      final cachedPair = (cached.book, cached.chapters);
      _initialData = cachedPair;
      _future = Future<(Book, List<Chapter>)>.value(cachedPair);
      _refreshInBackground(generation);
      return;
    }
    _initialData = null;
    _fromCache = false;
    _future = _source == null
        ? Future.error('未找到可用的来源源')
        : _fetchDetail(generation);
    _future.ignore();
  }

  /// 一键启用被禁用的来源源并重新加载（体检自动禁用后的死路解法）。
  Future<void> _enableSourceAndReload() async {
    final source = _findSource(includeDisabled: true);
    if (source == null) return;
    if (!source.enabled) await widget.appState.toggleSource(source.id);
    if (mounted) setState(_load);
  }

  Future<void> _openSources() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SourceScreen(state: widget.appState)),
    );
    if (mounted) setState(_load);
  }

  void _openReadingStats(Book book) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ComicReadingStatsScreen(
          stats: widget.appState.readingStats,
          sources: widget.appState.sources,
          book: book,
        ),
      ),
    );
  }

  void _openBookmarks({
    required Book book,
    required List<Chapter> chapters,
    required void Function(int index) openAt,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.7,
        ),
        child: ChapterBookmarkSheet(
          state: widget.appState,
          book: book,
          onPick: (bookmark) {
            final index = bookmark.indexIn(chapters);
            Navigator.of(sheetCtx).pop();
            if (index == null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('目录中找不到该书签对应的章节')));
              return;
            }
            openAt(index);
          },
        ),
      ),
    );
  }

  Future<void> _showDownloads(Book book, List<Chapter> chapters) async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DownloadSelectionSheet(
        state: widget.appState,
        book: book,
        chapters: chapters,
      ),
    );
    if (!mounted || added == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0 ? '所选章节已在下载队列中' : '已加入 $added 话下载'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DownloadsScreen(state: widget.appState),
              ),
            );
          },
        ),
      ),
    );
  }

  ComicSource? _findSource({bool includeDisabled = false}) {
    for (final s in widget.appState.sources) {
      if (s.id == widget.book.sourceId && (includeDisabled || s.enabled)) {
        return s;
      }
    }
    return null;
  }

  bool _isCurrentDetail(int generation) =>
      mounted && generation == _detailGeneration;

  Future<(Book, List<Chapter>)> _fetchDetail(int generation) async {
    final (book, chapters) = widget.detailLoaderOverride != null
        ? await widget.detailLoaderOverride!(widget.book.bookUrl)
        : await SourceService.instance
              .runtimeFor(_source!)
              .detail(widget.book.bookUrl);
    if (_isCurrentDetail(generation)) {
      await widget.appState.saveDetailCache(book, chapters);
    }
    return (book, chapters);
  }

  Future<void> _refreshInBackground(int generation) async {
    if (_source == null) return;
    try {
      final fresh = await _fetchDetail(generation);
      if (_isCurrentDetail(generation)) {
        setState(() {
          _fromCache = false;
          _future = Future<(Book, List<Chapter>)>.value(fresh);
        });
      }
    } catch (_) {
      // 保持当前内容；过时刷新失败也不能把较新的目录回退成旧缓存。
    }
  }

  /// 换源：在其它启用源中搜同名书，列表点选后替换当前详情页。
  /// 复用详情加载时的预扫缓存（无缓存/在途则共享同一次扫描）。
  Future<void> _showSwitchSourceSheet() async {
    final othersExist = widget.appState.sources.any(
      (s) =>
          s.enabled &&
          s.id != widget.book.sourceId &&
          s.rules.searchUrl.isNotEmpty,
    );
    if (!othersExist) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有其它启用的源可换')));
      return;
    }
    _scanSwitchTargets();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.of(sheetCtx).size.height * 0.7,
        child: ValueListenableBuilder<Future<List<(ComicSource, Book)>>?>(
          valueListenable: _switchTargets,
          builder: (context, pending, _) {
            return FutureBuilder<List<(ComicSource, Book)>>(
              key: ObjectKey(pending),
              future: pending,
              builder: (context, snap) => SwitchSourcePanel(
                bookName: widget.book.name,
                snapshot: snap,
                state: widget.appState,
                onRetry: () {
                  if (identical(_switchTargets.value, pending)) {
                    _scanSwitchTargets(refresh: true);
                  }
                },
                onPick: (source, b) {
                  if (!widget.appState.sources.any(
                    (s) => identical(s, source) && s.enabled,
                  )) {
                    return;
                  }
                  final carry = widget.appState
                      .progressFor(widget.book.bookUrl)
                      ?.chapterIndex;
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(this.context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => BookDetailScreen(
                        book: b,
                        appState: widget.appState,
                        carryChapterIndex: carry,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.appState, widget.appState.downloads]),
      builder: (context, _) => _buildDetail(context),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final currentSource = _findSource(includeDisabled: true);
    final sourceDisabled = currentSource?.enabled == false;
    final canRead = _source != null && currentSource?.enabled == true;
    final recoveryLabel = currentSource == null
        ? '管理源'
        : (sourceDisabled ? '启用漫画源' : '重新加载目录');
    final recoveryHint = currentSource == null
        ? '目录已保存在本地，恢复来源后即可阅读。'
        : (sourceDisabled ? '漫画源已停用，启用后即可继续阅读。' : '重新加载目录后，即可继续阅读。');
    final recoveryIcon = currentSource == null
        ? Icons.source_outlined
        : (sourceDisabled ? Icons.power_settings_new : Icons.refresh);
    final VoidCallback recoverSource = currentSource == null
        ? _openSources
        : (sourceDisabled ? _enableSourceAndReload : () => setState(_load));
    return Scaffold(
      body: SafeArea(
        top: false,
        child: FutureBuilder<(Book, List<Chapter>)>(
          future: _future,
          initialData: _initialData,
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(
                appBar: AppBar(title: Text(widget.book.name)),
                body: ErrorView(
                  title: sourceDisabled
                      ? '漫画源已停用'
                      : (currentSource == null ? '找不到这本书的来源' : '暂时无法加载漫画'),
                  message: sourceDisabled
                      ? '启用来源后，即可重新加载这本漫画。'
                      : (currentSource == null
                            ? '到「源」页添加或恢复来源后重试。'
                            : '检查网络后重试，或到「源」页查看来源状态。'),
                  onRetry: () => setState(_load),
                  icon: sourceDisabled
                      ? Icons.block_outlined
                      : Icons.cloud_off_outlined,
                  actionLabel: sourceDisabled
                      ? '启用「${currentSource!.name}」并重试'
                      : (currentSource == null ? '管理源' : null),
                  onAction: sourceDisabled || currentSource == null
                      ? recoverSource
                      : null,
                ),
              );
            }
            if (!snap.hasData) {
              // 骨架屏：结构对齐真实布局（封面块+文字条+章节行），秒开观感
              return Scaffold(
                appBar: AppBar(title: Text(widget.book.name)),
                body: const DetailSkeleton(),
              );
            }
            final (book, chapters) = snap.data!;
            _book ??= book;
            // 换源进度迁移：按章序号写入新书进度（一次性）
            if (widget.carryChapterIndex != null &&
                !_carryDone &&
                chapters.isNotEmpty) {
              _carryDone = true;
              final idx = widget.carryChapterIndex!.clamp(
                0,
                chapters.length - 1,
              );
              final c = chapters[idx];
              // ignore: unawaited_futures
              widget.appState.saveProgress(
                book,
                chapterUrl: c.url,
                chapterTitle: c.title,
                chapterIndex: idx,
                chapterCount: chapters.length,
              );
            }
            final scheme = Theme.of(context).colorScheme;
            final chapterNumberWidth = ChapterTile.numberWidthFor(
              context,
              chapters.length,
            );
            final prog = widget.appState.progressFor(widget.book.bookUrl);
            final savedIdx = (prog != null)
                ? chapters.indexWhere((c) => c.url == prog.chapterUrl)
                : -1;
            final offlineIndices = <int>{
              for (var i = 0; i < chapters.length; i++)
                if (widget.appState.downloads
                        .taskFor(book, chapters[i])
                        ?.status ==
                    DownloadStatus.completed)
                  i,
            };
            final hasOffline = offlineIndices.isNotEmpty;
            final resumeIndex = savedIdx >= 0 ? savedIdx : 0;
            final readIndex =
                !canRead && hasOffline && !offlineIndices.contains(resumeIndex)
                ? offlineIndices.first
                : resumeIndex;
            final bookmarkedUrls = {
              for (final bookmark in widget.appState.bookmarksFor(book))
                bookmark.chapter.url,
            };
            final bookmarkCount = widget.appState.bookmarksFor(book).length;
            final labelSource = _source ?? currentSource;
            final sourceName = labelSource == null
                ? null
                : (labelSource.name.trim().isEmpty
                      ? labelSource.id
                      : labelSource.name);
            final readLabel = chapters.isEmpty
                ? null
                : (canRead
                      ? (savedIdx >= 0 ? '续读 ${savedIdx + 1}' : '开始阅读')
                      : (hasOffline ? '离线阅读 ${readIndex + 1}' : recoveryLabel));
            void openAt(int index) {
              if (!canRead) {
                final task = widget.appState.downloads.taskFor(
                  book,
                  chapters[index],
                );
                if (task != null) {
                  openDownloadedChapter(context, widget.appState, task);
                }
                return;
              }
              openReader(
                context,
                SourceService.instance.runtimeFor(_source!),
                book,
                chapters,
                index,
                widget.appState,
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(book.name),
                actions: [
                  if (canRead &&
                      chapters.isNotEmpty &&
                      widget.appState.downloads.supported)
                    IconButton(
                      tooltip: '批量离线下载',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => _showDownloads(book, chapters),
                    ),
                  if (canRead)
                    Badge.count(
                      count: _switchCount ?? 0,
                      backgroundColor: scheme.primary,
                      textColor: scheme.onPrimary,
                      isLabelVisible: (_switchCount ?? 0) > 0,
                      child: IconButton(
                        tooltip:
                            '换源${_switchCount != null && _switchCount! > 0 ? '（$_switchCount 源命中）' : ''}',
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: _showSwitchSourceSheet,
                      ),
                    ),
                  if (canRead)
                    IconButton(
                      tooltip: '复制本书源 JSON（可分享）',
                      icon: const Icon(Icons.ios_share),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: sourceShareJson(_source!)),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制源 JSON，对方可在「源 → 剪贴板导入」粘贴使用'),
                            ),
                          );
                        }
                      },
                    ),
                  ShelfButton(book: book, state: widget.appState, iconSize: 24),
                ],
              ),
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        DetailHero(
                          book: book,
                          sourceName: sourceName,
                          switchCount: _switchCount,
                          onSwitchSource: canRead
                              ? _showSwitchSourceSheet
                              : null,
                          readLabel: readLabel,
                          readHint: canRead || hasOffline ? null : recoveryHint,
                          readIcon: canRead || hasOffline
                              ? Icons.play_arrow_rounded
                              : recoveryIcon,
                          onRead: readLabel == null
                              ? null
                              : (canRead || hasOffline
                                    ? () => openAt(readIndex)
                                    : recoverSource),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ListTile(
                            key: const Key('detail-reading-stats'),
                            leading: const Icon(Icons.bar_chart_outlined),
                            title: const Text('阅读统计'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openReadingStats(book),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ListTile(
                            key: const Key('detail-chapter-bookmarks'),
                            leading: const Icon(Icons.bookmark_outline),
                            title: const Text('书签'),
                            subtitle: Text(
                              bookmarkCount == 0
                                  ? '阅读时点顶栏书签即可添加'
                                  : '$bookmarkCount 话',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openBookmarks(
                              book: book,
                              chapters: chapters,
                              openAt: openAt,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            '章节 (${chapters.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_fromCache || !canRead)
                            Chip(
                              label: const Text(
                                '离线目录',
                                style: TextStyle(fontSize: 11),
                              ),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          if (chapters.length > 1)
                            Tooltip(
                              message: _chaptersReversed ? '切换为正序' : '切换为倒序',
                              child: TextButton.icon(
                                onPressed: () => setState(
                                  () => _chaptersReversed = !_chaptersReversed,
                                ),
                                icon: const Icon(Icons.swap_vert, size: 18),
                                label: Text(_chaptersReversed ? '倒序' : '正序'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (chapters.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateView(
                        icon: Icons.auto_stories_outlined,
                        title: '暂无章节',
                        message: canRead
                            ? '当前源还没有提供章节，可以重新加载或稍后再试。'
                            : recoveryHint,
                        actionLabel: canRead ? '重新加载' : recoveryLabel,
                        onAction: canRead
                            ? () => setState(_load)
                            : recoverSource,
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (context, i) {
                        final index = _chaptersReversed
                            ? chapters.length - 1 - i
                            : i;
                        return ChapterTile(
                          index: index,
                          numberWidth: chapterNumberWidth,
                          title: chapters[index].title,
                          isCurrent: index == savedIdx,
                          isBookmarked: bookmarkedUrls.contains(
                            chapters[index].url,
                          ),
                          onTap: canRead || offlineIndices.contains(index)
                              ? () => openAt(index)
                              : null,
                        );
                      },
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
