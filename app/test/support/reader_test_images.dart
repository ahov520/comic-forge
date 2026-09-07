import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 将可渲染的漫画页放入 Flutter 内存缓存，阅读器测试不访问网络或磁盘。
Future<void> cacheReaderTestImages(
  WidgetTester tester,
  Iterable<String> urls,
) async {
  final picture = ui.PictureRecorder();
  ui.Canvas(picture).drawColor(const ui.Color(0xFFDDDDDD), ui.BlendMode.src);
  final recording = picture.endRecording();
  final image = await tester.runAsync(() => recording.toImage(240, 480));
  recording.dispose();
  final cache = PaintingBinding.instance.imageCache;
  for (final url in urls) {
    cache.putIfAbsent(
      CachedNetworkImageProvider(url),
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: image!.clone())),
      ),
    );
  }
  image!.dispose();
  addTearDown(() {
    cache.clear();
    cache.clearLiveImages();
  });
}
