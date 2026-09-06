import 'dart:convert';

import 'js_lite.dart';

/// 单条选段规则：从上一步结果（节点/字符串）中继续提取。
class Seg {
  Seg({this.type, this.value = '', this.attr, this.fun, this.param, this.regex, this.replacement});

  /// css | xpath | json | shorthand(id./class./tag.) | attr | jstemplate
  final String? type;
  final String value;
  final String? attr;
  final String? fun;
  final String? param;
  final String? regex;
  final String? replacement;

  @override
  String toString() => 'Seg($type, $value${attr != null ? ", @$attr" : ""})';
}

/// 一条完整规则 = 若干 Seg 组成的管道；管道内多段依次执行，`||` 分隔的
/// 备选规则按序尝试直到非空，`&&` 分隔的规则结果合并。
class Rule {
  Rule(this.branches);

  /// 备选分支（`||`）；每个分支是合并组（`&&`），每组是一条 Seg 管道。
  final List<List<List<Seg>>> branches;

  bool get isEmpty => branches.isEmpty;

  /// 正则后处理（取首个分支末段 regex/replacement，H-Viewer 语义）。
  String? get lastRegex {
    for (final group in branches) {
      for (final pipe in group) {
        if (pipe.last.regex != null) return pipe.last.regex;
      }
    }
    return null;
  }

  String? get lastReplacement {
    for (final group in branches) {
      for (final pipe in group) {
        if (pipe.last.replacement != null) return pipe.last.replacement;
      }
    }
    return null;
  }
}

/// 规则字符串分析器。
///
/// 支持（v1 子集，对照 H-Viewer-RuleParser / legado 默认语法）：
/// - `@css:selector@attr`   显式 CSS
/// - `selector@attr`        默认按 CSS 处理
/// - `//a/@href`            XPath（以 `//` 或 `.` 开头）
/// - `$.data.list[*]`       JSONPath（以 `$.` 开头）
/// - `id.main@class.content@tag.a@text`  legado 简写
/// - `@text` `@html` `@href` `@src` `@attr:xxx` 提取函数
/// - `||` 备选，`&&` 合并
/// - ppcat：`{{js}}`/`@js:` 静态子集（js_lite）、`@put:{}` 剥离
class RuleAnalyzer {
  RuleAnalyzer(this.source);

  final String source;

  Rule parse() {
    final branches = <List<List<Seg>>>[];
    for (final alt in _splitTop(source, '||')) {
      final groups = <List<Seg>>[];
      for (final part in _splitTop(alt, '&&')) {
        final segs = _parsePipeline(part.trim());
        if (segs.isNotEmpty) groups.add(segs);
      }
      if (groups.isNotEmpty) branches.add(groups);
    }
    return Rule(branches);
  }

  /// 解析单条管道（不含 || 和 &&）。支持多级 @：
  /// `div.item@tag.a@text` = 选中 div.item → 在其中选 tag.a → 提取 text。
  /// 支持 legado 风格正则后处理后缀：`规则##正则##替换`。
  /// ppcat 扩展：`@put:{...}` 剥离；`{{...js...}}` 块静态求值；
  /// `前缀@js:...'+result+'...'` → jstemplate 段（求值期以 result 拼接）。
  List<Seg> _parsePipeline(String rule) {
    if (rule.isEmpty) return const [];

    // @put:{...} 变量存储暂不支持——剥离
    rule = _stripPutBlocks(rule);

    // {{...js...}} 块：js_lite 静态求值出一个规则串后重解析
    final block = RegExp(r'\{\{([\s\S]*?)\}\}').firstMatch(rule);
    if (block != null) {
      final evaluated = evalJsLite(block.group(1)!);
      if (evaluated == null || evaluated.isEmpty) return const [];
      var lit = evaluated;
      if (lit.startsWith(r'$.')) lit = normalizeJsonPathLiteral(lit);
      return _parsePipeline(rule.replaceRange(block.start, block.end, lit));
    }

    // @js: 后缀
    final jsIdx = rule.indexOf('@js:');
    if (jsIdx >= 0) {
      final prefix = rule.substring(0, jsIdx).trim();
      final js = rule.substring(jsIdx + 4);
      if (prefix.isEmpty) {
        // 纯 js 生成规则串（静态部分）
        final ev = evalJsLite(js);
        if (ev == null || ev.isEmpty) return const [];
        var lit = ev;
        if (lit.startsWith(r'$.')) lit = normalizeJsonPathLiteral(lit);
        return _parsePipeline(lit);
      }
      if (js.trim().isEmpty) return _parsePipeline(prefix);
      return [Seg(type: 'jstemplate', value: prefix, param: js)];
    }

    // ## 正则后处理后缀（不适用于 json/xpath 内部——先剥离再判断类型）
    String? postRegex;
    String? postReplacement;
    var body = rule;
    if (!body.startsWith('//') && !body.startsWith('\$.')) {
      final parts = _splitTop(body, '##');
      if (parts.length >= 2) {
        body = parts[0];
        postRegex = parts[1].trim();
        if (parts.length >= 3) postReplacement = parts[2];
      }
    }

    // JSONPath
    if (body.startsWith('\$.')) {
      return [Seg(type: 'json', value: body.substring(2))];
    }
    // XPath
    if (body.startsWith('//') || body.startsWith('./') || body.startsWith('(')) {
      return [Seg(type: 'xpath', value: body)];
    }

    String rest = body;
    String? type;
    if (rest.startsWith('@css:')) {
      type = 'css';
      rest = rest.substring(5);
    } else if (rest.startsWith('@XPath:')) {
      return [Seg(type: 'xpath', value: rest.substring(7))];
    }

    // 按 @ 拆步骤；末段若为提取函数则作为 attr 挂到最后一个选择步骤上。
    final tokens = _splitTop(rest, '@');
    String? attr;
    if (tokens.isNotEmpty && tokens.last.isNotEmpty) {
      final tail = tokens.last.trim();
      if (_isExtractFn(tail)) {
        attr = tail;
        tokens.removeLast();
      } else if (tail.startsWith('attr:')) {
        attr = tail.substring(5);
        tokens.removeLast();
      }
    }

    final segs = <Seg>[];
    for (final t in tokens) {
      final sel = t.trim();
      if (sel.isEmpty) continue;
      segs.add(Seg(type: type ?? _detect(sel), value: sel));
      type = null; // @css: 前缀只作用于第一段
    }
    if (segs.isEmpty) {
      if (attr != null) return [Seg(type: 'self', value: '', attr: attr, regex: postRegex, replacement: postReplacement)];
      return const [];
    }
    final last = segs.removeLast();
    segs.add(Seg(
      type: last.type,
      value: last.value,
      attr: attr ?? last.attr,
      regex: postRegex ?? last.regex,
      replacement: postReplacement ?? last.replacement,
    ));
    return segs;
  }

  static bool _isExtractFn(String s) =>
      s == 'text' || s == 'textNodes' || s == 'html' || s == 'all' ||
      s == 'href' || s == 'src' || s == 'content' || s == 'alt' || s == 'title' ||
      s == 'value' || s == 'textNodes';

  /// 剥离 `@put:{...}`（花括号配对扫描）。
  static String _stripPutBlocks(String rule) {
    var out = rule;
    while (true) {
      final i = out.indexOf('@put:');
      if (i < 0) return out;
      var b = out.indexOf('{', i);
      if (b < 0) return out.substring(0, i);
      var depth = 0;
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
      out = out.substring(0, i) + out.substring(e + 1);
    }
  }

  /// 宽容 JSON 对象解析（公开给 Header 语义使用）。
  static Map<String, String> lenientJsonMap(String raw) {
    if (raw.isEmpty) return {};
    final cleaned = raw.trim();
    try {
      final j = jsonDecode(cleaned);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    var s = cleaned.replaceAll('\'', '"');
    s = s.replaceAllMapped(
        RegExp(r'([{,]\s*)([A-Za-z0-9_\-]+)\s*:'), (m) => '${m.group(1)}"${m.group(2)}":');
    try {
      final j = jsonDecode(s);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
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

  static String _detect(String selector) {
    // legado 简写：id.xxx class.xxx tag.xxx
    if (selector.startsWith('id.') || selector.startsWith('class.') ||
        selector.startsWith('tag.')) {
      return 'shorthand';
    }
    return 'css';
  }
}

/// 顶层拆分（忽略引号与括号内的分隔符）。
List<String> _splitTop(String input, String sep) {
  if (input.isEmpty) return [''];
  final out = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quote != null) {
      buf.write(c);
      if (c == quote && !input.substring(0, i).endsWith('\\')) quote = null;
      continue;
    }
    if (c == '\'' || c == '"') {
      quote = c;
      buf.write(c);
      continue;
    }
    if (c == '(' || c == '[') depth++;
    if (c == ')' || c == ']') depth--;
    if (depth == 0 && input.startsWith(sep, i)) {
      out.add(buf.toString());
      buf.clear();
      i += sep.length - 1;
      continue;
    }
    buf.write(c);
  }
  out.add(buf.toString());
  return out;
}

/// URL 模板：`{{key}}` 占位符替换（searchUrl 的 {{key}}/{{page}}/{{pageSize}}）。
/// 兼容 ppcat 的裸 `searchKey` 占位与 `{page}` 单括号写法；
/// 数值变量支持 ppcat 算术偏移：`searchPage-1` / `{page+1}`；
/// `{{48*(searchPage-1)}}` 形式的纯算术表达式可求值。
String renderUrlTemplate(String template, Map<String, String> vars) {
  var out = template.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (m) {
    final expr = m.group(1)!.trim();
    final direct = vars[expr];
    if (direct != null) return direct;
    // 算术表达式：变量代入后若为纯数字运算则求值（如 48*(searchPage-1)）
    var e = expr;
    vars.forEach((k, v) {
      e = e.replaceAll(RegExp('\\b${RegExp.escape(k)}\\b'), v);
    });
    return evalArithmetic(e) ?? '';
  });
  // 算术偏移：仅数值变量（page/searchPage 等页码），避免误伤搜索词。
  // 括号只在成对时剥离；单侧的 { 或 } 属于外围文本（如 JSON 体），原样保留。
  vars.forEach((name, value) {
    final n = int.tryParse(value);
    if (n == null) return;
    out = out.replaceAllMapped(
        RegExp('(\\{)?\\b${RegExp.escape(name)}\\b\\s*([+-])\\s*(\\d+)(\\})?'),
        (m) {
      final open = m.group(1) ?? '';
      final close = m.group(4) ?? '';
      final v = m.group(2) == '+'
          ? n + int.parse(m.group(3)!)
          : n - int.parse(m.group(3)!);
      // 成对括号 = 占位符本身的包裹（{page+1}），剥离；单侧 = 外围文本（JSON 体），保留
      return open.isNotEmpty && close.isNotEmpty ? '$v' : '$open$v$close';
    });
  });
  out = out.replaceAllMapped(RegExp(r'\{\s*(\w+)\s*\}'), (m) {
    return vars[m.group(1)] ?? m.group(0)!;
  });
  final sk = vars['key'];
  if (sk != null && sk.isNotEmpty) {
    out = out.replaceFirst('searchKey', sk);
  }
  final sp = vars['searchPage'];
  if (sp != null && sp.isNotEmpty) {
    out = out.replaceFirst('searchPage', sp);
  }
  return out;
}

/// 规则字符串工具入口（供 evaluator 与测试使用）。
RuleAnalyzer analyzer(String rule) => RuleAnalyzer(rule);

/// 求值纯算术表达式（整数四则 + 括号，如 `48*(searchPage-1)` 代入后的
/// `48*(2-1)`）。表达式含任何非运算字符则返回 null（不抛错、不 eval）。
String? evalArithmetic(String expr) {
  final v = _ArithEval(expr.replaceAll(RegExp(r'\s+'), '')).parseAll();
  return v;
}

class _ArithEval {
  _ArithEval(this.s);

  final String s;
  int pos = 0;

  String? parseAll() {
    final v = parseExpr();
    if (v == null || pos != s.length) return null;
    return '$v';
  }

  // expr := term (('+'|'-') term)*
  int? parseExpr() {
    final first = parseTerm();
    if (first == null) return null;
    int v = first;
    while (pos < s.length && (s[pos] == '+' || s[pos] == '-')) {
      final op = s[pos++];
      final r = parseTerm();
      if (r == null) return null;
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  // term := unary (('*'|'/'|'%') unary)*
  int? parseTerm() {
    final first = parseUnary();
    if (first == null) return null;
    int v = first;
    while (pos < s.length && (s[pos] == '*' || s[pos] == '/' || s[pos] == '%')) {
      final op = s[pos++];
      final r = parseUnary();
      if (r == null) return null;
      if ((op == '/' || op == '%') && r == 0) return null;
      if (op == '*') {
        v = v * r;
      } else if (op == '/') {
        v = v ~/ r;
      } else {
        v = v % r;
      }
    }
    return v;
  }

  // unary := ('-'|'+')* atom
  int? parseUnary() {
    if (pos < s.length && s[pos] == '-') {
      pos++;
      final v = parseUnary();
      return v == null ? null : -v;
    }
    if (pos < s.length && s[pos] == '+') {
      pos++;
      return parseUnary();
    }
    return parseAtom();
  }

  // atom := '(' expr ')' | number
  int? parseAtom() {
    if (pos < s.length && s[pos] == '(') {
      pos++;
      final v = parseExpr();
      if (v == null || pos >= s.length || s[pos] != ')') return null;
      pos++;
      return v;
    }
    final start = pos;
    while (pos < s.length && RegExp(r'[0-9]').hasMatch(s[pos])) {
      pos++;
    }
    if (pos == start) return null;
    return int.parse(s.substring(start, pos));
  }
}

/// 便捷判定：规则是否指向 JSON 数据（用于 evaluator 选择解析器）。
bool looksLikeJsonRule(String rule) => rule.trim().startsWith('\$.');
