import 'package:engine/engine.dart';

/// 源编辑器表单 → [ComicSource] 的纯构建/校验逻辑（可单测，不涉 UI）。
class SourceForm {
  SourceForm._();

  /// 仅允许 http/https 且 host 为公网域名/公网 IPv4；
  /// 拒绝 localhost、环回、私有与保留地址（Mimosa 安全约束）。
  static bool isPublicHttpUrl(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null) return false;
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    final host = u.host;
    if (host.isEmpty || !host.contains('.')) return false;
    if (host == 'localhost' || host.endsWith('.localhost')) return false;
    if (host.endsWith('.local') || host.endsWith('.internal')) return false;
    final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (ip != null) {
      final o = [1, 2, 3, 4].map((i) => int.parse(ip.group(i)!)).toList();
      if (o.any((x) => x > 255)) return false;
      if (o[0] == 0 || o[0] == 10 || o[0] == 127) return false;
      if (o[0] == 169 && o[1] == 254) return false;
      if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return false;
      if (o[0] == 192 && o[1] == 168) return false;
      if (o[0] >= 224) return false;
      return true;
    }
    if (host.contains(':')) return false; // IPv6 字面量不支持（编辑器场景）
    return true;
  }

  /// 表单数据。
  static SourceBuildResult build({
    String? existingId,
    required String name,
    required String url,
    String group = '',
    String headers = '',
    String searchUrl = '',
    String searchList = '',
    String searchName = '',
    String searchAuthor = '',
    String searchCoverUrl = '',
    String searchBookUrl = '',
    String findUrl = '',
    String chapterList = '',
    String chapterName = '',
    String chapterUrl = '',
    String contentUrl = '',
    String contentUrlNext = '',
  }) {
    final n = name.trim();
    final u = url.trim();
    if (n.isEmpty) return const SourceBuildError('名称必填');
    if (u.isEmpty) return const SourceBuildError('源地址必填');
    if (!isPublicHttpUrl(u)) {
      return const SourceBuildError('源地址须为 http/https 公网地址');
    }
    if (searchUrl.trim().isEmpty && findUrl.trim().isEmpty) {
      return const SourceBuildError('搜索 URL 与发现 URL 至少填一个');
    }

    // headers：每行 `Key: Value` 或 `Key=Value`
    final h = <String, String>{};
    for (var raw in headers.split('\n')) {
      raw = raw.trim();
      if (raw.isEmpty) continue;
      final i = raw.indexOf(RegExp('[:=]'));
      if (i <= 0) continue;
      final k = raw.substring(0, i).trim();
      final v = raw.substring(i + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) h[k] = v;
    }

    final id = existingId?.isNotEmpty == true ? existingId! : u;
    final s = ComicSource(
      id: id,
      name: n,
      group: group.trim(),
      url: u,
      headers: h,
    );
    s.rules
      ..searchUrl = searchUrl.trim()
      ..searchList = searchList.trim()
      ..searchName = searchName.trim()
      ..searchAuthor = searchAuthor.trim()
      ..searchCoverUrl = searchCoverUrl.trim()
      ..searchBookUrl = searchBookUrl.trim()
      ..findUrl = findUrl.trim()
      ..chapterList = chapterList.trim()
      ..chapterName = chapterName.trim()
      ..chapterUrl = chapterUrl.trim()
      ..contentUrl = contentUrl.trim()
      ..contentUrlNext = contentUrlNext.trim();
    return SourceBuilt(s);
  }
}

/// 构建结果：成功携带源，失败携带用户可读错误。
sealed class SourceBuildResult {
  const SourceBuildResult();
}

class SourceBuilt extends SourceBuildResult {
  const SourceBuilt(this.source);
  final ComicSource source;
}

class SourceBuildError extends SourceBuildResult {
  const SourceBuildError(this.message);
  final String message;
}
