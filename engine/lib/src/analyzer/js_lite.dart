/// 极小 JS 子集求值器（js_lite）。
///
/// ppcat 源里大量 `{{...js...}}` / `@js:` 片段其实只做两件事：
/// 1. 按条件挑选一个静态规则串（`var out='$.data.list.*'; ... out`）
/// 2. 用 `result`（前缀规则提取值）做字符串拼接生成 URL/规则
///    （`'https://x/api@{"id":'+result+'}@PostJson'`）
///
/// 本求值器覆盖这两类，不求值任意 JS：
/// - `var x='字面量';` 顺序赋值（单/双引号）
/// - `'a'+result+'b'` 拼接（result 为前缀提取值）
/// - `if(...){...}` 块整体跳过（仅保留静态默认值语义）
/// - 末尾裸标识符语句返回对应变量；无法解析返回 null
library;

String? evalJsLite(String js, {String? result}) {
  final s = _stripComments(js);
  // 收集 var 赋值；拼接表达式即时求值
  final vars = <String, String>{};
  // if 块移除（其内部的 var 不参与——静态默认值已在外层）
  final cleaned = _removeIfBlocks(s);
  final varRe = RegExp(r'var\s+([A-Za-z_$][\w$]*)\s*=\s*([^;]+);');
  for (final m in varRe.allMatches(cleaned)) {
    final v = _evalConcatExpr(m.group(2)!.trim(), result);
    // 不可求值的 var（如 JSON.parse(result)、java.ajax(...)）跳过，
    // 只要最终取到的静态默认值不依赖它们即可
    if (v == null) continue;
    vars[m.group(1)!] = v;
  }
  if (vars.isEmpty) {
    // 无 var：整段可能是单个拼接表达式
    final v = _evalConcatExpr(cleaned, result);
    if (v != null) return v;
    return null;
  }
  // 末尾裸标识符语句（`out;` / `out`）
  final trailing =
      RegExp(r'([A-Za-z_$][\w$]*)\s*;?\s*$').firstMatch(_stripVarStmts(cleaned));
  if (trailing != null && vars.containsKey(trailing.group(1))) {
    return vars[trailing.group(1)];
  }
  // 否则取最后一个 var 的值（常见 `var out=...` 收尾）
  return vars.values.last;
}

String _stripComments(String s) {
  // `://` 是 URL 协议分隔，不是行注释
  return s
      .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
}

/// 移除 if(...){...} 与 else{...} 块（花括号配对）。
String _removeIfBlocks(String s) {
  var out = s;
  while (true) {
    final i = out.indexOf(RegExp(r'\bif\s*\('));
    if (i < 0) break;
    // 找到 if 的配对小括号
    var depth = 0;
    var j = out.indexOf('(', i);
    var k = j;
    for (; k < out.length; k++) {
      if (out[k] == '(') {
        depth++;
      } else if (out[k] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (k >= out.length) return out.substring(0, i);
    // 找配对花括号
    var b = out.indexOf('{', k);
    if (b < 0) {
      out = out.substring(0, i) + out.substring(k + 1);
      continue;
    }
    depth = 0;
    var e = b;
    for (; e < out.length; e++) {
      if (out[e] == '{') {
        depth++;
      } else if (out[e] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (e >= out.length) return out.substring(0, i);
    // 跳过紧随的 else{...}
    var end = e + 1;
    final elseM = RegExp(r'^\s*else\s*\{').firstMatch(out.substring(end));
    if (elseM != null) {
      var b2 = end + elseM.end - 1;
      depth = 0;
      var e2 = b2;
      for (; e2 < out.length; e2++) {
        if (out[e2] == '{') {
          depth++;
        } else if (out[e2] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      end = e2 + 1;
    }
    out = out.substring(0, i) + out.substring(end);
  }
  return out;
}

/// 表达式求值：字符串字面量与 result 的拼接；其他算术/函数调用不支持。
String? _evalConcatExpr(String expr, String? result) {
  final parts = <String>[];
  var i = 0;
  while (i < expr.length) {
    final c = expr[i];
    if (RegExp(r'\s').hasMatch(c)) {
      i++;
      continue;
    }
    if (c == '+') {
      i++;
      continue;
    }
    if (c == '\'' || c == '"') {
      final quote = c;
      final buf = StringBuffer();
      i++;
      while (i < expr.length && expr[i] != quote) {
        if (expr[i] == r'\' && i + 1 < expr.length) {
          i++; // 简单转义
        }
        buf.write(expr[i]);
        i++;
      }
      if (i >= expr.length) return null; // 未闭合
      i++;
      parts.add(buf.toString());
      continue;
    }
    // 标识符：仅支持 result（其余视为不可解析，除非是纯数字）
    final m = RegExp(r'^[A-Za-z_$][\w$]*').firstMatch(expr.substring(i));
    if (m != null) {
      final name = m.group(0)!;
      if (name == 'result') {
        if (result == null) return null;
        parts.add(result);
        i += name.length;
        continue;
      }
      return null;
    }
    final num0 = RegExp(r'^\d+').firstMatch(expr.substring(i));
    if (num0 != null) {
      parts.add(num0.group(0)!);
      i += num0.end;
      continue;
    }
    return null; // 未知记号（函数调用/算术等）→ 不支持
  }
  return parts.join();
}

/// 去掉已收集的 var 语句，便于找末尾裸标识符。
String _stripVarStmts(String s) {
  return s.replaceAll(RegExp(r'var\s+([A-Za-z_$][\w$]*)\s*=\s*[^;]+;'), '');
}

/// 把 ppcat 风格 jsonpath 规范化为引擎 jsonpath：
/// `$.a.b.*|$.c` → `$.a.b[*]||$.c[*]`（`.*`→`[*]`，单 `|`→`||`）。
String normalizeJsonPathLiteral(String literal) {
  var v = literal.trim();
  if (!v.startsWith(r'$.')) return v;
  final alts = v.split('|').map((p) {
    var t = p.trim();
    t = t.replaceAll('.*', '[*]');
    if (!t.startsWith(r'$.')) t = '.$t';
    return t;
  }).toList();
  return alts.join('||');
}
