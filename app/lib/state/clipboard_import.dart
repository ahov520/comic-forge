import 'dart:convert';

import 'package:engine/engine.dart';

/// 剪贴板规则 JSON 导入的纯解析逻辑（可单测，不涉 UI/剪贴板）。
///
/// 接受：
/// - 单条：ppcat 平铺（bookSourceName/ruleSearchUrl…）或嵌套（{name,url,rules:{}}）
/// - 数组：多条混合形态
/// 解析失败的条目跳过；全部无效返回 [ClipboardImportInvalid]。
sealed class ClipboardImportResult {
  const ClipboardImportResult();
}

/// 单条 → 打开编辑器预填（用户确认后保存）。
class ClipboardImportSingle extends ClipboardImportResult {
  const ClipboardImportSingle(this.source);
  final ComicSource source;
}

/// 多条 → 直接批量导入。
class ClipboardImportMany extends ClipboardImportResult {
  const ClipboardImportMany(this.sources);
  final List<ComicSource> sources;
}

class ClipboardImportInvalid extends ClipboardImportResult {
  const ClipboardImportInvalid(this.message);
  final String message;
}

class ClipboardSourceImport {
  ClipboardSourceImport._();

  static ClipboardImportResult parse(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      return const ClipboardImportInvalid('剪贴板为空');
    }
    dynamic j;
    try {
      j = jsonDecode(t);
    } on FormatException {
      return const ClipboardImportInvalid('不是合法 JSON');
    }
    final List<Map<String, dynamic>> maps;
    if (j is List) {
      maps = j.whereType<Map<String, dynamic>>().toList();
    } else if (j is Map<String, dynamic>) {
      maps = [j];
    } else {
      return const ClipboardImportInvalid('JSON 结构不是源对象或数组');
    }

    final sources = <ComicSource>[];
    for (final m in maps) {
      final s = _fromMap(m);
      if (s != null) sources.add(s);
    }
    if (sources.isEmpty) {
      return const ClipboardImportInvalid('未找到可识别的源（需要名称与地址字段）');
    }
    return sources.length == 1
        ? ClipboardImportSingle(sources.first)
        : ClipboardImportMany(sources);
  }

  /// 条目 → 源：要求能解析出非空 id（url/源地址）与名称。
  static ComicSource? _fromMap(Map<String, dynamic> m) {
    try {
      final s = _looksPpcatFlat(m)
          ? ComicSource.fromPpcatFlat(m)
          : ComicSource.fromJson(m);
      if (s.id.isEmpty || s.name.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  static bool _looksPpcatFlat(Map<String, dynamic> m) =>
      m.containsKey('ruleSearchList') ||
      m.containsKey('ruleFindList') ||
      m.containsKey('ruleId') ||
      m.containsKey('bookSourceName');
}
