import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'skeleton.dart';

/// 单张漫画图片可独立重试，保留同话中其它图片和阅读位置。
class ReaderNetworkImage extends StatefulWidget {
  const ReaderNetworkImage({
    super.key,
    required this.imageUrl,
    required this.pageNumber,
    required this.headers,
    this.fit = BoxFit.fitWidth,
  });

  final String imageUrl;
  final int pageNumber;
  final Map<String, String> headers;
  final BoxFit fit;

  @override
  State<ReaderNetworkImage> createState() => _ReaderNetworkImageState();
}

class _ReaderNetworkImageState extends State<ReaderNetworkImage> {
  var _attempt = 0;
  bool _retrying = false;

  File? get _localFile {
    final uri = Uri.tryParse(widget.imageUrl);
    return uri?.scheme == 'file' ? File.fromUri(uri!) : null;
  }

  @override
  void didUpdateWidget(covariant ReaderNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _retrying = false;
  }

  Future<void> _retry() async {
    if (_retrying) return;
    final url = widget.imageUrl;
    setState(() => _retrying = true);
    final local = _localFile;
    if (local != null) {
      await FileImage(local).evict();
      if (!mounted || widget.imageUrl != url) return;
      setState(() {
        _attempt++;
        _retrying = false;
      });
      return;
    }
    try {
      await CachedNetworkImage.evictFromCache(url);
    } catch (_) {
      // 磁盘缓存不可用时仍尝试重新取图。
      await CachedNetworkImageProvider(url).evict();
    }
    if (!mounted || widget.imageUrl != url) return;
    setState(() {
      _attempt++;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final safe = MediaQuery.paddingOf(context);
    Widget failure(BuildContext context) => Padding(
      // 翻页模式的重试操作避开工具栏，横屏/大字号下仍可滚动到按钮。
      padding: widget.fit == BoxFit.contain
          ? EdgeInsets.fromLTRB(
              safe.left,
              safe.top + 64,
              safe.right,
              safe.bottom + 80,
            )
          : EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 200),
        child: Center(
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  '第 ${widget.pageNumber} 张图片加载失败',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _retrying ? null : _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(_retrying ? '重试中…' : '重试图片'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final local = _localFile;
    if (local != null) {
      return Image.file(
        local,
        key: ValueKey((widget.imageUrl, _attempt)),
        fit: widget.fit,
        errorBuilder: (context, _, _) => failure(context),
      );
    }
    return CachedNetworkImage(
      key: ValueKey((widget.imageUrl, _attempt)),
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      httpHeaders: widget.headers,
      fadeInDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 120),
      fadeOutDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 120),
      placeholder: (_, _) => SizedBox(
        height: widget.fit == BoxFit.contain ? double.infinity : 240,
        child: const Center(child: SkeletonBox(height: 220)),
      ),
      errorWidget: (context, _, _) => failure(context),
    );
  }
}
