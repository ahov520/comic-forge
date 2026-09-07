import 'dart:convert';

/// 可解码的 2×2 PNG，下载测试覆盖真正的校验和文件写入。
List<int> downloadTestImage() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGNoaGj4D8IMMAYAVvQJ/UtL6SwAAAAASUVORK5CYII=',
);
