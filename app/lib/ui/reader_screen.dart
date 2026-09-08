import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/scroll_restore.dart';
import '../state/download_queue.dart';
import 'reader_chrome.dart';
import 'reader_image_page.dart';
import 'reader_network_image.dart';
import 'skeleton.dart';
import 'widgets.dart' show EmptyStateView;

/// 音量键翻页通道（Android 原生拦截后转发）。
const _readerChannel = MethodChannel('comic-forge/reader');

/// 章节阅读器：连续滚动 / 左右翻页两种模式，点击切换工具栏；
/// 支持上一话/下一话、阅读进度记忆、预加载下一话、亮度调节、音量键翻页。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.runtime,
    required this.book,
    required this.chapters,
    required this.initialIndex,
    this.appState,
  });

  final SourceRuntime runtime;
  final Book book;
  final List<Chapter> chapters;
  final int initialIndex;
  final AppState? appState;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _index;
  late Future<List<String>> _images;
  bool _chromeVisible = true;
  var _pageController = PageController(keepPage: false);
  final _scrollController = ScrollController();
  bool _nextChapterWarmed = false;
  bool _offsetRestored = false;
  double? _scrollRestoreTarget;
  int _scrollRestoreGeneration = 0;
  bool _scrollRestoreScheduled = false;
  bool _applyingScrollRestore = false;
  Timer? _offsetSaveTimer;
  bool _volumeKeysEnabled = false;
  late bool _wasPaged;
  String? _scrollChapterUrl;
  double? _scrollViewportWidth;
  double _scrollTopInset = 0;
  double? _lastScrollOffset;
  String? _pagedChapterUrl;
  int _pageCount = 0;
  int _pageIndex = 0;
  bool _pageZoomed = false;

  Chapter get _chapter => widget.chapters[_index];

  bool get _isPaged => widget.appState?.readerMode == 'paged';

  @override
  void initState() {
    super.initState();
    _wasPaged = _isPaged;
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _loadChapter(_index, save: true);
    // 音量键翻页（Android）：仅阅读器打开期间激活
    widget.appState?.addListener(_onReaderSettingsChanged);
    _syncVolumeKeys();
    _readerChannel.setMethodCallHandler(_onVolumeKey);
    // 滚动模式：接近底部预热下一话（翻页模式由 onPageChanged 触发）
    _scrollController.addListener(_warmNextChapterOnScroll);
  }

  Future<void> _onVolumeKey(MethodCall call) async {
    if (!mounted || !_volumeKeysEnabled) return;
    if (call.method == 'volumeUp') {
      _pageTurn(-1);
    } else if (call.method == 'volumeDown') {
      _pageTurn(1);
    }
  }

  void _enableVolumeKeys(bool enabled) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _readerChannel.invokeMethod('setVolumeKeysEnabled', {'enabled': enabled});
  }

  void _syncVolumeKeys() {
    final enabled = widget.appState?.readerVolumeKeys == true;
    if (enabled == _volumeKeysEnabled) return;
    _volumeKeysEnabled = enabled;
    _enableVolumeKeys(enabled);
  }

  void _onReaderSettingsChanged() {
    if (_wasPaged != _isPaged) {
      _saveCurrentScrollOffset();
      _lastScrollOffset = null;
      _offsetSaveTimer?.cancel();
      _cancelScrollRestore();
      _offsetRestored = false;
      _wasPaged = _isPaged;
      _pagedChapterUrl = null;
      _pageIndex = 0;
      _pageZoomed = false;
    }
    _syncVolumeKeys();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState?.removeListener(_onReaderSettingsChanged);
      widget.appState?.addListener(_onReaderSettingsChanged);
      _syncVolumeKeys();
    }
  }

  /// 逐页或逐屏翻动，到本话边界后再切换章节。
  void _pageTurn(int delta) {
    if (_isPaged) {
      if (!_pageController.hasClients || _pageCount == 0) return;
      final page = (_pageController.page ?? 0).round() + delta;
      if (page < 0 || page >= _pageCount) {
        _go(delta);
        return;
      }
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!_scrollController.hasClients) return;
    _cancelScrollRestore();
    final position = _scrollController.position;
    if ((delta < 0 && position.extentBefore < 1) ||
        (delta > 0 && position.extentAfter < 1)) {
      _go(delta);
      return;
    }
    _scrollController.animateTo(
      (position.pixels + position.viewportDimension * 0.85 * delta)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _loadChapter(int index, {bool save = false, bool refresh = false}) {
    _saveCurrentScrollOffset();
    _lastScrollOffset = null;
    _offsetSaveTimer?.cancel();
    _cancelScrollRestore();
    _pageCount = 0;
    _pagedChapterUrl = null;
    _pageIndex = 0;
    _pageZoomed = false;
    setState(() {
      _index = index;
      _chromeVisible = true;
      _images = _imagesForChapter(widget.chapters[index], refresh: refresh);
      // 下一帧才订阅；即时失败或提前切话也要接住异常，界面仍能读取错误。
      _images.ignore();
    });
    _nextChapterWarmed = false;
    _offsetRestored = false;
    // 预加载下一话 URL 列表（失败静默）
    if (index + 1 < widget.chapters.length && !_downloaded(index + 1)) {
      SourceService.instance.prefetchImages(
        widget.runtime,
        widget.chapters[index + 1].url,
      );
    }
    if (save && widget.appState != null) {
      widget.appState!.saveProgress(
        widget.book,
        chapterUrl: _chapter.url,
        chapterTitle: _chapter.title,
        chapterIndex: index,
        chapterCount: widget.chapters.length,
      );
    }
  }

  bool _downloaded(int index) =>
      widget.appState?.downloads
          .taskFor(widget.book, widget.chapters[index])
          ?.status ==
      DownloadStatus.completed;

  Future<List<String>> _imagesForChapter(
    Chapter chapter, {
    required bool refresh,
  }) async {
    final offline = await widget.appState?.downloads.offlineImages(
      widget.book,
      chapter,
      adBlock: SourceService.instance.adBlock,
    );
    if (offline != null) return offline;
    return SourceService.instance.imagesFor(
      widget.runtime,
      chapter.url,
      refresh: refresh,
    );
  }

  /// 接近本章末页时预热下一话图片字节（每章只触发一次）。
  void _warmNextChapterIfNeeded(int page, int pageCount) {
    if (_nextChapterWarmed) return;
    if (page < pageCount - 2) return;
    final next = _index + 1;
    if (next >= widget.chapters.length) return;
    if (_downloaded(next)) return;
    _nextChapterWarmed = true;
    SourceService.instance.prefetchImages(
      widget.runtime,
      widget.chapters[next].url,
    );
    SourceService.instance.precacheLeadingImages(
      context,
      widget.runtime,
      widget.chapters[next].url,
    );
  }

  /// 滚动模式接近底部时同样触发（由 ScrollController 调用）。
  void _warmNextChapterOnScroll() {
    _saveOffsetDebounced();
    if (_nextChapterWarmed) return;
    final c = _scrollController;
    if (!c.hasClients) return;
    if (c.position.maxScrollExtent - c.offset < 800) {
      final next = _index + 1;
      if (next >= widget.chapters.length) return;
      if (_downloaded(next)) return;
      _nextChapterWarmed = true;
      SourceService.instance.prefetchImages(
        widget.runtime,
        widget.chapters[next].url,
      );
      SourceService.instance.precacheLeadingImages(
        context,
        widget.runtime,
        widget.chapters[next].url,
      );
    }
  }

  /// 滚动位置节流保存（停顿 600ms 落盘一次）。
  void _saveOffsetDebounced() {
    if (_isPaged) return;
    final c = _scrollController;
    if (!c.hasClients) return;
    _lastScrollOffset = c.offset;
    if (_scrollRestoreTarget != null) return;
    final chapterUrl = _scrollChapterUrl;
    final position = c.position;
    final width = _scrollViewportWidth;
    final topInset = _scrollTopInset;
    if (chapterUrl == null) return;
    _offsetSaveTimer?.cancel();
    _offsetSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted ||
          !c.hasClients ||
          !identical(c.position, position) ||
          _scrollChapterUrl != chapterUrl) {
        return;
      }
      widget.appState?.saveScrollOffset(
        chapterUrl,
        position.pixels,
        viewportWidth: width,
        topInset: topInset,
      );
    });
  }

  void _saveCurrentScrollOffset() {
    if (_scrollRestoreTarget != null) return;
    final url = _scrollChapterUrl;
    if (url == null) return;
    // dispose 时子列表可能已断开控制器，仍要保存尚未到节流时间的位置。
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : _lastScrollOffset;
    if (offset == null) return;
    widget.appState?.saveScrollOffset(
      url,
      offset,
      viewportWidth: _scrollViewportWidth,
      topInset: _scrollTopInset,
    );
  }

  void _prepareScrollLayout(double width, double topInset) {
    final previousWidth = _scrollViewportWidth;
    final resized =
        previousWidth != null &&
        (previousWidth != width || _scrollTopInset != topInset);
    final restoring = !_offsetRestored;
    if (restoring) {
      _offsetRestored = true;
      final saved = widget.appState?.scrollOffsetFor(
        _chapter.url,
        viewportWidth: width,
        topInset: topInset,
      );
      if (saved != null && saved.isFinite && saved > 0) {
        _scrollRestoreTarget = saved;
      }
    } else if (resized && _scrollController.hasClients) {
      final offset = _scrollRestoreTarget ?? _scrollController.offset;
      _offsetSaveTimer?.cancel();
      final previousTop = _scrollTopInset;
      _cancelScrollRestore();
      _scrollRestoreTarget = resizeScrollOffset(
        offset: offset,
        fromWidth: previousWidth,
        toWidth: width,
        fromTopInset: previousTop,
        toTopInset: topInset,
      );
    }
    _scrollViewportWidth = width;
    _scrollTopInset = topInset;
    if ((restoring || resized) && _scrollRestoreTarget != null) {
      // 保存换算后的目标，不能写入图片尚未展开时被临时截短的位置。
      widget.appState?.saveScrollOffset(
        _chapter.url,
        _scrollRestoreTarget!,
        viewportWidth: width,
        topInset: topInset,
      );
      _scheduleScrollRestore();
    }
  }

  void _cancelScrollRestore() {
    _scrollRestoreTarget = null;
    _scrollRestoreGeneration++;
    _scrollRestoreScheduled = false;
  }

  /// 图片尺寸渐进确定时继续恢复原偏移；用户主动滚动后停止。
  void _scheduleScrollRestore() {
    if (_scrollRestoreTarget == null || _scrollRestoreScheduled) return;
    final generation = _scrollRestoreGeneration;
    final chapterUrl = _scrollChapterUrl;
    _scrollRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _scrollRestoreGeneration) return;
      _scrollRestoreScheduled = false;
      final saved = _scrollRestoreTarget;
      if (!mounted ||
          _isPaged ||
          saved == null ||
          chapterUrl != _chapter.url ||
          !_scrollController.hasClients) {
        return;
      }
      final target = resolveRestoredScroll(
        saved: saved,
        maxExtent: _scrollController.position.maxScrollExtent,
      );
      if ((_scrollController.offset - target).abs() < 0.5) return;
      _applyingScrollRestore = true;
      try {
        _scrollController.jumpTo(target);
      } finally {
        _applyingScrollRestore = false;
      }
    });
    // 尺寸通知可能在帧结束后到达，主动安排下一帧执行恢复。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    _loadChapter(next, save: true);
  }

  @override
  void dispose() {
    widget.appState?.removeListener(_onReaderSettingsChanged);
    // 退出阅读器时立即落盘当前滚动位置
    _saveCurrentScrollOffset();
    _offsetSaveTimer?.cancel();
    _cancelScrollRestore();
    if (_volumeKeysEnabled) _enableVolumeKeys(false);
    _readerChannel.setMethodCallHandler(null);
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 正文渲染：滚动模式 = ListView；翻页模式 = PageView + 三分点区。
  Widget _buildReaderBody(BuildContext context, List<String> urls) {
    _pageCount = urls.length;
    Widget img(int i, {BoxFit fit = BoxFit.fitWidth}) => ReaderNetworkImage(
      key: ValueKey('${_chapter.url}:$i:${urls[i]}'),
      imageUrl: urls[i],
      pageNumber: i + 1,
      fit: fit,
      // 防盗链：源 headers + 内容规则尾部 @Header（Referer 等）
      headers: {
        ...widget.runtime.source.headers,
        ...widget.runtime.imageRequestHeaders,
      },
    );

    if (!_isPaged) {
      final chapterUrl = _chapter.url;
      _scrollChapterUrl = chapterUrl;
      return LayoutBuilder(
        builder: (context, constraints) {
          final padding = MediaQuery.paddingOf(context);
          _prepareScrollLayout(constraints.maxWidth, padding.top);
          return GestureDetector(
            onTap: () => setState(() => _chromeVisible = !_chromeVisible),
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _scheduleScrollRestore();
                return false;
              },
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  // 图片高度修正后的自动回弹不是用户接管滚动。
                  if (notification.depth == 0 &&
                      !_applyingScrollRestore &&
                      (notification.dragDetails != null ||
                          !notification.metrics.outOfRange)) {
                    _cancelScrollRestore();
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  // 宽度变化时丢弃旧图片高度的布局测量，再恢复同一阅读位置。
                  key: PageStorageKey((
                    chapterUrl,
                    constraints.maxWidth,
                    padding.top,
                  )),
                  padding: EdgeInsets.only(
                    top: padding.top,
                    bottom: 64 + padding.bottom,
                  ),
                  itemCount: urls.length,
                  itemBuilder: (context, i) => img(i),
                ),
              ),
            ),
          );
        },
      );
    }

    final chapterUrl = _chapter.url;
    if (_pagedChapterUrl != chapterUrl) {
      final previous = _pageController;
      _pageIndex = (widget.appState?.readerPageFor(chapterUrl) ?? 0).clamp(
        0,
        urls.length - 1,
      );
      _pageController = PageController(
        initialPage: _pageIndex,
        keepPage: false,
      );
      _pagedChapterUrl = chapterUrl;
      widget.appState?.saveReaderPage(chapterUrl, _pageIndex);
      // 旧 PageView 在本帧结束前仍可能持有控制器。
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    final pages = _pageController;

    // 翻页模式：点击左 1/3 = 上一页，中 = 工具栏，右 1/3 = 下一页；
    // 末页右翻进入下一话（已到末话则提示）。
    return PageView.builder(
      key: ObjectKey(pages),
      controller: pages,
      physics: _pageZoomed ? const NeverScrollableScrollPhysics() : null,
      itemCount: urls.length,
      onPageChanged: (i) {
        if (!mounted ||
            !_isPaged ||
            _pagedChapterUrl != chapterUrl ||
            !identical(pages, _pageController)) {
          return;
        }
        setState(() {
          _pageIndex = i;
          _pageZoomed = false;
        });
        widget.appState?.saveReaderPage(chapterUrl, i);
        _warmNextChapterIfNeeded(i, urls.length);
      },
      itemBuilder: (context, i) {
        final isLast = i == urls.length - 1;
        return ReaderImagePage(
          key: ValueKey('${_chapter.url}:$i'),
          active: i == _pageIndex,
          onPrevious: () => _pageTurn(-1),
          onNext: () {
            if (!isLast || _index + 1 < widget.chapters.length) {
              _pageTurn(1);
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已是最后一话')));
            }
          },
          onToggleChrome: () =>
              setState(() => _chromeVisible = !_chromeVisible),
          onZoomChanged: (zoomed) {
            if (i == _pageIndex && zoomed != _pageZoomed) {
              setState(() => _pageZoomed = zoomed);
            }
          },
          child: Center(child: img(i, fit: BoxFit.contain)),
        );
      },
    );
  }

  String get _chromeTitle => '${widget.book.name} · ${_chapter.title}';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF169876),
          brightness: Brightness.dark,
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF161619),
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Builder(builder: _buildReader),
      ),
    );
  }

  Widget _buildReader(BuildContext context) {
    final brightness = widget.appState?.readerBrightness ?? 1.0;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      // 跳转弹窗自行避让键盘，正文保持原尺寸和阅读位置。
      resizeToAvoidBottomInset: false,
      body: FutureBuilder<List<String>>(
        future: _images,
        builder: (context, snap) {
          final pad = MediaQuery.paddingOf(context);
          final showStatus =
              snap.connectionState == ConnectionState.done &&
              (snap.hasError || snap.data?.isEmpty == true);
          Widget status({required bool failed}) => Padding(
            padding: EdgeInsets.fromLTRB(pad.left, pad.top + 64, pad.right, 16),
            child: EmptyStateView(
              icon: failed
                  ? Icons.cloud_off_outlined
                  : Icons.image_not_supported_outlined,
              title: failed ? '暂时无法加载章节' : '本话暂无图片',
              message: failed
                  ? (snap.error is BlockedHostException
                        ? (snap.error as BlockedHostException).userMessage
                        : '检查网络后重试，或从目录选择其它章节。')
                  : '可以重试加载，或从目录选择其它章节。',
              actionLabel: '重试',
              onAction: () => _loadChapter(_index, refresh: true),
            ),
          );
          final Widget page;
          if (snap.connectionState != ConnectionState.done) {
            page = Semantics(
              label: '正在加载章节',
              liveRegion: true,
              child: const Center(
                child: SkeletonBox(width: 160, height: 220, radius: 12),
              ),
            );
          } else if (snap.hasError) {
            page = status(failed: true);
          } else {
            final urls = snap.data!;
            if (urls.isEmpty) {
              page = status(failed: false);
            } else {
              page = _buildReaderBody(context, urls);
            }
          }
          final bottomChrome = ReaderBottomChrome(
            visible: _chromeVisible,
            progressLabel: '${_index + 1}/${widget.chapters.length}',
            canPrev: _index > 0,
            canNext: _index + 1 < widget.chapters.length,
            onPrev: () => _go(-1),
            onNext: () => _go(1),
            onCatalog: () => _showCatalog(context),
            onBrightness: widget.appState == null
                ? null
                : () => _showReaderSettingsSheet(context),
          );
          final body = Stack(
            children: [
              page,
              if (!showStatus)
                ReaderChromeOverlay(
                  visible: _chromeVisible,
                  topInset: pad.top,
                  bottomInset: pad.bottom,
                ),
              if (brightness < 1.0)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - brightness),
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          );
          return Stack(
            children: [
              if (showStatus)
                // 空态和重试入口避让底栏的实际高度，包括大字号多行计数。
                Column(
                  children: [
                    Expanded(child: body),
                    bottomChrome,
                  ],
                )
              else
                body,
              Positioned(
                top: pad.top,
                left: pad.left + 12,
                right: pad.right + 12,
                child: ReaderTopChrome(
                  visible: _chromeVisible,
                  title: _chromeTitle,
                  onMore: widget.appState == null
                      ? null
                      : () => _showReaderSettingsSheet(context),
                ),
              ),
              if (!showStatus)
                Positioned(left: 0, right: 0, bottom: 0, child: bottomChrome),
            ],
          );
        },
      ),
    );
  }

  void _showCatalog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF161619),
      showDragHandle: true,
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.7,
        ),
        child: ReaderCatalogSheet(
          chapters: widget.chapters,
          currentIndex: _index,
          onPick: (i) {
            Navigator.of(sheetCtx).pop();
            if (i != _index) _loadChapter(i, save: true);
          },
        ),
      ),
    );
  }

  /// 阅读设置面板：亮度 / 模式切换 / 音量键翻页开关。
  void _showReaderSettingsSheet(BuildContext context) {
    final appState = widget.appState;
    if (appState == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF161619),
      builder: (sheetCtx) => AnimatedBuilder(
        animation: appState,
        builder: (context, _) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.brightness_low,
                      color: Colors.white54,
                      size: 18,
                    ),
                    Expanded(
                      child: Slider(
                        value: appState.readerBrightness,
                        min: 0.15,
                        max: 1.0,
                        semanticFormatterCallback: (value) =>
                            '亮度 ${(value * 100).round()}%',
                        onChanged: appState.setReaderBrightness,
                      ),
                    ),
                    const Icon(
                      Icons.brightness_high,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
                Text(
                  '亮度 ${(appState.readerBrightness * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Divider(color: Colors.white24),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'scroll',
                      icon: Icon(Icons.swap_vert, size: 18),
                      label: Text('滚动'),
                    ),
                    ButtonSegment(
                      value: 'paged',
                      icon: Icon(Icons.swap_horiz, size: 18),
                      label: Text('翻页'),
                    ),
                  ],
                  selected: {appState.readerMode},
                  onSelectionChanged: (s) => appState.setReaderMode(s.first),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: Colors.white70,
                  title: const Text(
                    '音量键翻页',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  subtitle: const Text(
                    '音量+ 上一页 · 音量- 下一页（Android）',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  value: appState.readerVolumeKeys,
                  onChanged: appState.setReaderVolumeKeys,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
