import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/source_share.dart';
import 'detail_chrome.dart';
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
  ComicSource? _disabledSource; // 来源源存在但被禁用 → 提供一键启用
  bool _fromCache = false;
  bool _carryDone = false;
  int? _switchCount; // 换源可命中数（后台预扫完成后显示角标）
  /// 缓存命中时首帧直出的数据（避免 FutureBuilder 首帧闪骨架）。
  (Book, List<Chapter>)? _initialData;

  @override
  void initState() {
    super.initState();
    _load();
    _scanSwitchTargets();
  }

  /// 后台预扫换源目标（结果入 SourceService 缓存，面板复用；失败静默）。
  Future<void> _scanSwitchTargets() async {
    try {
      final r = await SourceService.instance.scanSwitchTargets(
        book: widget.book,
        allSources: widget.appState.sources,
      );
      if (mounted) setState(() => _switchCount = r.length);
    } catch (_) {
      // 静默：角标不显示也不影响换源面板（面板会再扫）
    }
  }

  void _load() {
    _book = null;
    _source = _findSource();
    _disabledSource = null;
    if (_source == null) {
      for (final s in widget.appState.sources) {
        if (s.id == widget.book.sourceId && !s.enabled) {
          _disabledSource = s;
          break;
        }
      }
    }
    final cached = widget.appState.detailCacheFor(widget.book.bookUrl);
    if (cached != null) {
      // stale-while-revalidate：先秒开缓存，再后台刷新（失败静默回退缓存）。
      // initialData 让 FutureBuilder 首帧即有数据——缓存命中不闪骨架。
      _fromCache = true;
      final cachedPair = (cached.book, cached.chapters);
      _initialData = cachedPair;
      _future = Future<(Book, List<Chapter>)>.value(cachedPair);
      _refreshInBackground(cachedPair);
      return;
    }
    _initialData = null;
    _fromCache = false;
    _future = _source == null ? Future.error('未找到可用的来源源') : _fetchDetail();
  }

  /// 一键启用被禁用的来源源并重新加载（体检自动禁用后的死路解法）。
  Future<void> _enableSourceAndReload() async {
    final id = _disabledSource?.id;
    if (id == null) return;
    await widget.appState.toggleSource(id);
    if (mounted) setState(_load);
  }

  void _openSources() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SourceScreen(state: widget.appState)),
  );

  ComicSource? _findSource() {
    for (final s in widget.appState.sources) {
      if (s.id == widget.book.sourceId && s.enabled) return s;
    }
    return null;
  }

  Future<(Book, List<Chapter>)> _fetchDetail() async {
    final (book, chapters) = widget.detailLoaderOverride != null
        ? await widget.detailLoaderOverride!(widget.book.bookUrl)
        : await SourceService.instance
              .runtimeFor(_source!)
              .detail(widget.book.bookUrl);
    await widget.appState.saveDetailCache(book, chapters);
    return (book, chapters);
  }

  Future<void> _refreshInBackground((Book, List<Chapter>) cachedPair) async {
    if (_source == null) return;
    try {
      final fresh = await _fetchDetail();
      if (mounted) {
        setState(() {
          _fromCache = false;
          _future = Future<(Book, List<Chapter>)>.value(fresh);
        });
      }
    } catch (_) {
      // 网络失败：保持缓存内容，不打断阅读
      _future = Future<(Book, List<Chapter>)>.value(cachedPair);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.of(sheetCtx).size.height * 0.7,
        child: FutureBuilder<List<(ComicSource, Book)>>(
          future: SourceService.instance.scanSwitchTargets(
            book: widget.book,
            allSources: widget.appState.sources,
          ),
          builder: (context, snap) => SwitchSourcePanel(
            bookName: widget.book.name,
            snapshot: snap,
            state: widget.appState,
            onPick: (_, b) {
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<(Book, List<Chapter>)>(
        future: _future,
        initialData: _initialData,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.book.name)),
              body: ErrorView(
                title: _disabledSource != null
                    ? '漫画源已停用'
                    : (_source == null ? '找不到这本书的来源' : '暂时无法加载漫画'),
                message: _disabledSource != null
                    ? '启用来源后，即可重新加载这本漫画。'
                    : (_source == null
                          ? '到「源」页添加或恢复来源后重试。'
                          : '检查网络后重试，或到「源」页查看来源状态。'),
                onRetry: () => setState(_load),
                icon: _disabledSource != null
                    ? Icons.block_outlined
                    : Icons.cloud_off_outlined,
                actionLabel: _disabledSource != null
                    ? '启用「${_disabledSource!.name}」并重试'
                    : (_source == null ? '管理源' : null),
                onAction: _disabledSource != null
                    ? _enableSourceAndReload
                    : (_source == null ? _openSources : null),
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
            final idx = widget.carryChapterIndex!.clamp(0, chapters.length - 1);
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
          final prog = widget.appState.progressFor(widget.book.bookUrl);
          final savedIdx = (prog != null)
              ? chapters.indexWhere((c) => c.url == prog.chapterUrl)
              : -1;
          final sourceName = _source == null
              ? null
              : (_source!.name.trim().isEmpty ? _source!.id : _source!.name);
          final readLabel = chapters.isEmpty
              ? null
              : (savedIdx >= 0 ? '续读 ${savedIdx + 1}' : '开始阅读');
          void openAt(int index) {
            if (_source == null) return;
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
                if (_source != null)
                  Badge.count(
                    count: _switchCount ?? 0,
                    isLabelVisible: (_switchCount ?? 0) > 0,
                    child: IconButton(
                      tooltip:
                          '换源${_switchCount != null && _switchCount! > 0 ? '（$_switchCount 源命中）' : ''}',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: _showSwitchSourceSheet,
                    ),
                  ),
                if (_source != null)
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
                  child: DetailHero(
                    book: book,
                    sourceName: sourceName,
                    switchCount: _switchCount,
                    onSwitchSource: _source == null
                        ? null
                        : _showSwitchSourceSheet,
                    readLabel: readLabel,
                    onRead: readLabel == null
                        ? null
                        : () => openAt(savedIdx >= 0 ? savedIdx : 0),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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
                        if (_fromCache)
                          Chip(
                            label: const Text(
                              '离线目录',
                              style: TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: scheme.surfaceContainerHighest,
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
                      message: _source == null
                          ? '添加或启用来源后，重新打开这本漫画。'
                          : '当前源还没有提供章节，可以重新加载或稍后再试。',
                      actionLabel: _source == null ? '管理源' : '重新加载',
                      onAction: _source == null
                          ? _openSources
                          : () => setState(_load),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: chapters.length,
                    itemBuilder: (context, i) {
                      return ChapterTile(
                        index: i,
                        title: chapters[i].title,
                        isCurrent: i == savedIdx,
                        onTap: () => openAt(i),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          );
        },
      ),
    );
  }
}
