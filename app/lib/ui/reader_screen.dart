import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/scroll_restore.dart';
import 'reader_chrome.dart';
import 'skeleton.dart';

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
  final _pageController = PageController();
  final _scrollController = ScrollController();
  bool _nextChapterWarmed = false;
  bool _offsetRestored = false;
  Timer? _offsetSaveTimer;

  Chapter get _chapter => widget.chapters[_index];

  bool get _isPaged => widget.appState?.readerMode == 'paged';

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _loadChapter(_index, save: true);
    // 音量键翻页（Android）：仅阅读器打开期间激活
    _enableVolumeKeys(true);
    _readerChannel.setMethodCallHandler(_onVolumeKey);
    // 滚动模式：接近底部预热下一话（翻页模式由 onPageChanged 触发）
    _scrollController.addListener(_warmNextChapterOnScroll);
  }

  Future<void> _onVolumeKey(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'volumeUp') {
      _pageTurn(-1);
    } else if (call.method == 'volumeDown') {
      _pageTurn(1);
    }
  }

  void _enableVolumeKeys(bool enabled) {
    if (widget.appState?.readerVolumeKeys != true) return;
    if (!Platform.isAndroid) return;
    _readerChannel.invokeMethod('setVolumeKeysEnabled', {'enabled': enabled});
  }

  /// 翻一“屏”：翻页模式走 PageView，滚动模式直接跨话。
  void _pageTurn(int delta) {
    if (_isPaged) {
      final page =
          (_pageController.hasClients ? _pageController.page ?? 0 : 0) + delta;
      if (page < 0) return;
      _pageController.animateToPage(
        page.round(),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    _go(delta);
  }

  void _loadChapter(int index, {bool save = false}) {
    setState(() {
      _index = index;
      _images = SourceService.instance.imagesFor(
        widget.runtime,
        widget.chapters[index].url,
      );
    });
    _nextChapterWarmed = false;
    _offsetRestored = false;
    _offsetSaveTimer?.cancel();
    // 预加载下一话 URL 列表（失败静默）
    if (index + 1 < widget.chapters.length) {
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

  /// 接近本章末页时预热下一话图片字节（每章只触发一次）。
  void _warmNextChapterIfNeeded(int page, int pageCount) {
    if (_nextChapterWarmed) return;
    if (page < pageCount - 2) return;
    final next = _index + 1;
    if (next >= widget.chapters.length) return;
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
    _offsetSaveTimer?.cancel();
    _offsetSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!c.hasClients || widget.appState == null) return;
      widget.appState!.saveScrollOffset(_chapter.url, c.offset);
    });
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    _loadChapter(next, save: true);
  }

  @override
  void dispose() {
    // 退出阅读器时立即落盘当前滚动位置
    if (!_isPaged && _scrollController.hasClients && widget.appState != null) {
      widget.appState!.saveScrollOffset(_chapter.url, _scrollController.offset);
    }
    _offsetSaveTimer?.cancel();
    _enableVolumeKeys(false);
    _readerChannel.setMethodCallHandler(null);
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 正文渲染：滚动模式 = ListView；翻页模式 = PageView + 三分点区。
  Widget _buildReaderBody(BuildContext context, List<String> urls) {
    Widget img(String url, {BoxFit fit = BoxFit.fitWidth}) =>
        CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          // 防盗链：源 headers + 内容规则尾部 @Header（Referer 等）
          httpHeaders: {
            ...widget.runtime.source.headers,
            ...widget.runtime.imageRequestHeaders,
          },
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, _) => SizedBox(
            height: fit == BoxFit.contain ? double.infinity : 240,
            child: const Center(child: SkeletonBox(height: 220)),
          ),
          errorWidget: (_, _, _) => const SizedBox(
            height: 200,
            child: Center(
              child: Text('图片加载失败', style: TextStyle(color: Colors.white38)),
            ),
          ),
        );

    if (!_isPaged) {
      return GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: ListView.builder(
          controller: _scrollController,
          key: PageStorageKey<String>(_chapter.url),
          itemCount: urls.length,
          itemBuilder: (context, i) {
            // 首帧后恢复持久化的滚动位置（跨重启记忆，每章一次）
            if (!_offsetRestored) {
              _offsetRestored = true;
              final saved = widget.appState?.scrollOffsetFor(_chapter.url);
              if (saved != null && saved > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      resolveRestoredScroll(
                        saved: saved,
                        maxExtent: _scrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                });
              }
            }
            return img(urls[i]);
          },
        ),
      );
    }

    // 翻页模式：点击左 1/3 = 上一页，中 = 工具栏，右 1/3 = 下一页；
    // 末页右翻进入下一话（已到末话则提示）。
    Widget pageContent(int i) => InteractiveViewer(
      maxScale: 4,
      child: Center(child: img(urls[i], fit: BoxFit.contain)),
    );
    return PageView.builder(
      controller: _pageController,
      itemCount: urls.length,
      onPageChanged: (i) {
        setState(() {});
        _warmNextChapterIfNeeded(i, urls.length);
      },
      itemBuilder: (context, i) {
        final isLast = i == urls.length - 1;
        return Stack(
          children: [
            pageContent(i),
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => i > 0
                          ? _pageController.previousPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            )
                          : _go(-1),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _chromeVisible = !_chromeVisible),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!isLast) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        } else if (_index + 1 < widget.chapters.length) {
                          _go(1); // 跨章：翻到末页继续右翻 = 下一话
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已是最后一话')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String get _chromeTitle =>
      '${widget.runtime.source.name} · ${widget.book.name} · ${_chapter.title}';

  @override
  Widget build(BuildContext context) {
    final brightness = widget.appState?.readerBrightness ?? 1.0;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E),
      body: FutureBuilder<List<String>>(
        future: _images,
        builder: (context, snap) {
          final Widget page;
          var showBottom = false;
          if (snap.hasError) {
            page = Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '加载失败：${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _loadChapter(_index),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          } else if (!snap.hasData) {
            page = const Center(
              child: SkeletonBox(width: 160, height: 220, radius: 12),
            );
          } else {
            final urls = snap.data!;
            if (urls.isEmpty) {
              page = const Center(
                child: Text(
                  '本章节解析不到图片（源规则可能不完整）',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              );
            } else {
              showBottom = true;
              page = _buildReaderBody(context, urls);
            }
          }
          final pad = MediaQuery.of(context).padding;
          return Stack(
            children: [
              page,
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
              Positioned(
                top: pad.top + 8,
                left: 12,
                right: 12,
                child: ReaderTopChrome(
                  visible: _chromeVisible,
                  title: _chromeTitle,
                  onMore: widget.appState == null
                      ? null
                      : () => _showReaderSettingsSheet(context),
                ),
              ),
              if (showBottom)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: pad.bottom + 12,
                  child: ReaderBottomChrome(
                    visible: _chromeVisible,
                    progressLabel: '${_index + 1}/${widget.chapters.length}',
                    canPrev: _index > 0,
                    canNext: _index + 1 < widget.chapters.length,
                    onPrev: () => _go(-1),
                    onNext: () => _go(1),
                    onBrightness: widget.appState == null
                        ? null
                        : () => _showReaderSettingsSheet(context),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 阅读设置面板：亮度 / 模式切换 / 音量键翻页开关。
  void _showReaderSettingsSheet(BuildContext context) {
    final appState = widget.appState;
    if (appState == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (sheetCtx) => AnimatedBuilder(
        animation: appState,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
    );
  }
}
