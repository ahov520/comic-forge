import 'dart:convert';

/// 从规则 URL 解析出的完整请求（ppcat/H-Viewer `@` 约定）。
class SourceRequest {
  SourceRequest({
    required this.url,
    this.method = 'GET',
    this.body = '',
    this.headers = const {},
  });

  final String url;
  final String method; // GET | POST
  final String body;
  final Map<String, String> headers;

  bool get isPost => method.toUpperCase() == 'POST';
}

/// 解析 ppcat/H-Viewer 风格的规则 URL：
/// - `url`                              → GET
/// - `url@k=v&k2=v2`                    → POST form（application/x-www-form-urlencoded）
/// - `url@{json}` 或 `url@{json}@PostJson` → POST JSON
/// - `url@…@Header:{...}`               → 附加请求头（键可不带引号，宽容解析）
/// - `url@PostJson@{json}` / `url@Post@表单体` 也接受（标记位置不限）
SourceRequest parseRuleUrl(String raw, {Map<String, String>? headers}) {
  final parts = _splitTopAt(raw.trim());
  final url = parts.isNotEmpty ? parts[0].trim() : '';
  final req = SourceRequest(
      url: url, headers: headers != null ? Map.of(headers) : {});

  final rest = parts.skip(1).toList();
  String? jsonBody;
  String? formBody;

  for (final p in rest) {
    final part = p.trim();
    if (part.isEmpty) continue;
    if (part.startsWith('Header:') || part.startsWith('header:')) {
      req.headers.addAll(_parseLenientJsonMap(part.substring(7).trim()));
    } else if (part.toLowerCase() == 'postjson') {
      req.headers.putIfAbsent('Content-Type', () => 'application/json');
    } else if (part.toLowerCase() == 'post' || part.toLowerCase() == 'postform') {
      // 标记 POST form；体在其余部分
    } else if (part.startsWith('{') || part.startsWith('[')) {
      jsonBody = part;
    } else if (part.contains('=')) {
      formBody = part;
    } else if (part.toLowerCase() == 'nofetch') {
      // ppcat: 占位入口，不发起请求（保留 URL，交由调用方决定）
    }
  }

  if (jsonBody != null) {
    req.headers.putIfAbsent(
        'Content-Type', () => 'application/json;charset=UTF-8');
    return SourceRequest(
        url: req.url, method: 'POST', body: jsonBody, headers: req.headers);
  }
  if (formBody != null) {
    req.headers.putIfAbsent(
        'Content-Type', () => 'application/x-www-form-urlencoded');
    return SourceRequest(
        url: req.url, method: 'POST', body: formBody, headers: req.headers);
  }
  return req;
}

/// 顶层 `@` 拆分（忽略引号与 JSON 花括号内的 @）。
List<String> _splitTopAt(String input) {
  final out = <String>[];
  final buf = StringBuffer();
  var braceDepth = 0;
  String? quote;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quote != null) {
      buf.write(c);
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == '\'') {
      quote = c;
      buf.write(c);
      continue;
    }
    if (c == '{' || c == '[') braceDepth++;
    if (c == '}' || c == ']') braceDepth--;
    if (c == '@' && braceDepth == 0) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  out.add(buf.toString());
  return out;
}

/// 宽容 JSON 对象解析：允许无引号键/单引号（`{Cookie:"a=2"}` 这类手写体）。
/// 解析失败则尝试 `k:v` / `k=v` 逗号拆分，仍失败返回空表。
Map<String, String> _parseLenientJsonMap(String raw) {
  if (raw.isEmpty) return {};
  final cleaned = raw.trim();
  try {
    final j = jsonDecode(cleaned);
    if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v.toString()));
  } catch (_) {}
  // 单引号 → 双引号、补齐裸键
  var s = cleaned.replaceAll('\'', '"');
  s = s.replaceAllMapped(RegExp(r'([{,]\s*)([A-Za-z0-9_\-]+)\s*:'),
      (m) => '${m.group(1)}"${m.group(2)}":');
  try {
    final j = jsonDecode(s);
    if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v.toString()));
  } catch (_) {}
  // k:v,k2:v2 兜底
  final out = <String, String>{};
  for (final kv in cleaned.replaceAll(RegExp(r'^\{|\}$'), '').split(',')) {
    final i = kv.indexOf(RegExp('[:=]'));
    if (i <= 0) continue;
    final k = kv.substring(0, i).trim().replaceAll('"', '').replaceAll('\'', '');
    final v = kv.substring(i + 1).trim().replaceAll('"', '').replaceAll('\'', '');
    if (k.isNotEmpty) out[k] = v;
  }
  return out;
}
