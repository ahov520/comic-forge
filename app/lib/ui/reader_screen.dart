import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';

/// 章节阅读器：图片流连续滚动，点击切换工具栏；
/// 支持上一话/下一话、阅读进度记忆、预加载下一话。
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

  Chapter get _chapter => widget.chapters[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.chapters.length - 1);
    _loadChapter(_index, save: true);
  }

  void _loadChapter(int index, {bool save = false}) {
    setState(() {
      _index = index;
      _images = SourceService.instance
          .imagesFor(widget.runtime, widget.chapters[index].url);
    });
    // 预加载下一话（失败静默）
    if (index + 1 < widget.chapters.length) {
      SourceService.instance
          .prefetchImages(widget.runtime, widget.chapters[index + 1].url);
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

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    _loadChapter(next, save: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<String>>(
        future: _images,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载失败：${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _loadChapter(_index),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final urls = snap.data!;
          if (urls.isEmpty) {
            return const Center(
                child: Text('本章节解析不到图片（源规则可能不完整）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)));
          }
          return Stack(
            children: [
              GestureDetector(
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                child: ListView.builder(
                  itemCount: urls.length,
                  itemBuilder: (context, i) => Image.network(
                    urls[i],
                    fit: BoxFit.fitWidth,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 200,
                      child: Center(
                          child: Text('图片加载失败',
                              style: TextStyle(color: Colors.white38))),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity: _chromeVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    children: [
                      const CloseButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          '${widget.book.name} · ${_index + 1}/${widget.chapters.length} ${_chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: AnimatedOpacity(
                  opacity: _chromeVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    children: [
                      IconButton(
                        color: Colors.white,
                        tooltip: '上一话',
                        onPressed: _index > 0 ? () => _go(-1) : null,
                        icon: const Icon(Icons.skip_previous_outlined),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_index + 1} / ${widget.chapters.length}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                      IconButton(
                        color: Colors.white,
                        tooltip: '下一话',
                        onPressed: _index + 1 < widget.chapters.length
                            ? () => _go(1)
                            : null,
                        icon: const Icon(Icons.skip_next_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
