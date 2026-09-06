import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';

/// 章节阅读器：图片流连续滚动，点击切换工具栏。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.runtime,
    required this.book,
    required this.chapter,
    this.appState,
  });

  final SourceRuntime runtime;
  final Book book;
  final Chapter chapter;
  final AppState? appState;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Future<List<String>> _images;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    final src = widget.runtime.source;
    _images = SourceGuard.track(
      src,
      () => widget.runtime.images(widget.chapter.url),
    ).whenComplete(() => widget.appState?.persistSources());
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
                child: Text('加载失败：${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
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
                      CloseButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          '${widget.book.name} · ${widget.chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
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
