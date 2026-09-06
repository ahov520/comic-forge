import 'dart:convert';

import 'package:engine/engine.dart';

/// 源分享 JSON：优先原始平铺 JSON（ppcat 形态保真），手建源退回嵌套
/// toJson 并剥离健康字段噪音。产物可直接经「剪贴板导入」还原。
String sourceShareJson(ComicSource s) {
  if (s.raw.isNotEmpty) {
    return const JsonEncoder.withIndent('  ').convert(s.raw);
  }
  final j = Map<String, dynamic>.of(s.toJson())
    ..remove('lastError')
    ..remove('lastFailedAt')
    ..remove('failCount')
    ..remove('lastOkAt');
  return const JsonEncoder.withIndent('  ').convert(j);
}
