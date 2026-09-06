import 'dart:convert';

import 'package:html/dom.dart' as hd;

import 'rule_analyzer.dart';

/// 在 [root] 上评估规则，返回提取到的全部字符串。
///
/// [root] 可为：
/// - `hd.Document` / `hd.Element`（HTML）
/// - `List`/`Map`/标量（JSON，经 [jsonDecode]）
/// - `String`（纯文本，仅可被 regex/常量规则消费）
class RuleEvaluator {
  const RuleEvaluator();

  /// 返回全部命中（字符串化）。
  List<String> eval(dynamic root, Rule rule) {
    final out = _evalBranches(root, rule)
        .map(_stringify)
        .where((s) => s.isNotEmpty)
        .toList();
    return _applyPost(rule.lastRegex, rule.lastReplacement, out);
  }

  /// 返回第一个非空命中（无则 null）。
  String? evalFirst(dynamic root, Rule rule) {
    for (final v in eval(root, rule)) {
      if (v.trim().isNotEmpty) return v;
    }
    return null;
  }

  /// 列表规则专用：返回原始节点（Element/Map/…），供子规则继续求值。
  List<dynamic> evalNodes(dynamic root, Rule rule) => _evalBranches(root, rule);

  List<dynamic> _evalBranches(dynamic root, Rule rule) {
    for (final group in rule.branches) {
      final out = <dynamic>[];
      for (final pipe in group) {
        out.addAll(_evalPipeline(root, pipe));
      }
      if (out.any((n) => _stringify(n).trim().isNotEmpty)) return out;
    }
    return const [];
  }

  List<dynamic> _evalPipeline(dynamic node, List<Seg> pipe) {
    var cur = <dynamic>[node];
    for (final seg in pipe) {
      final next = <dynamic>[];
      for (final n in cur) {
        next.addAll(_evalSeg(n, seg));
      }
      cur = next;
      if (cur.isEmpty) return const [];
    }
    // json 路径末段命中数组（如 `$.data.hit`，无 [*]）时摊平为逐项节点，
    // 列表规则的 ppcat/legado 语义是迭代数组元素。
    if (cur.length == 1 && cur.first is List) {
      return (cur.first as List).toList();
    }
    return cur;
  }

  List<dynamic> _evalSeg(dynamic node, Seg seg) {
    switch (seg.type) {
      case 'json':
        return _evalJsonPath(node, seg.value);
      case 'xpath':
        return _evalXPath(node, seg.value, seg.attr);
      case 'css':
      case 'shorthand':
      case 'self':
        return _evalCss(node, seg);
      default:
        return const [];
    }
  }

  // ---------- HTML / CSS ----------

  List<dynamic> _evalCss(dynamic node, Seg seg) {
    if (node is String) return const [];
    hd.Element scope;
    if (node is hd.Document) {
      final el = node.documentElement;
      if (el == null) return const [];
      scope = el;
    } else if (node is hd.Element) {
      scope = node;
    } else {
      return const [];
    }
    final attr = seg.attr;
    if (seg.type == 'self' || seg.value.isEmpty) {
      return [if (attr != null) _extract(scope, attr) else scope];
    }

    Iterable<hd.Element> selected;
    if (seg.type == 'shorthand') {
      selected = _evalShorthand(scope, seg.value);
    } else {
      try {
        selected = scope.querySelectorAll(seg.value);
      } on Exception {
        return const [];
      }
    }
    if (attr == null) return selected.toList();
    return selected.map((e) => _extract(e, attr)).toList();
  }

  /// legado 简写：`id.x` `class.x`（多类匹配）`tag.x`，支持尾部数字下标
  /// （`tag.span.0` = 第 0 个 span）。
  Iterable<hd.Element> _evalShorthand(hd.Element scope, String shorthand) sync* {
    final dot = shorthand.indexOf('.');
    if (dot < 0) return;
    final kind = shorthand.substring(0, dot);
    final rest = shorthand.substring(dot + 1);
    final parts = rest.split('.');
    // 尾部数字 = 下标
    int? index;
    if (parts.isNotEmpty && int.tryParse(parts.last) != null) {
      index = int.parse(parts.last);
      parts.removeLast();
    }
    if (parts.isEmpty) return;
    final first = parts.first;
    final tail = parts.length > 1 ? '.${parts.skip(1).join('.')}' : '';
    Iterable<hd.Element> selected;
    switch (kind) {
      case 'id':
        selected = scope.querySelectorAll('#$first$tail');
      case 'class':
        final classes = parts.where((p) => p.isNotEmpty).toList();
        selected = scope.querySelectorAll('*').where((e) {
          final cl = e.classes;
          return classes.every(cl.contains);
        });
      case 'tag':
        selected = scope.querySelectorAll(parts.join('.'));
      default:
        return;
    }
    if (index != null) {
      if (index < selected.length) yield selected.elementAt(index);
    } else {
      yield* selected;
    }
  }

  String _extract(hd.Element e, String fn) {
    switch (fn) {
      case 'text':
        return e.text.trim();
      case 'textNodes':
        final buf = StringBuffer();
        for (final n in e.nodes) {
          if (n is hd.Text) buf.write(n.text.trim());
        }
        return buf.toString().trim();
      case 'html':
        return e.innerHtml;
      case 'all':
        return e.outerHtml;
      case 'href':
      case 'src':
      case 'content':
      case 'alt':
      case 'title':
      case 'value':
        return e.attributes[fn] ?? '';
      default:
        if (fn.startsWith('attr:')) return e.attributes[fn.substring(5)] ?? '';
        return e.attributes[fn] ?? '';
    }
  }

  // ---------- XPath（子集） ----------

  /// 支持子集：`//tag` `/tag` `.//tag` `*` `[n]` `[@attr='v']` `[@attr]`
  /// `[@class~='v']` `contains(@attr,'v')`，尾部 `/@attr` 提取属性；
  /// `text()` 取文本。
  List<dynamic> _evalXPath(dynamic node, String expr, String? attr) {
    hd.Element scope;
    if (node is hd.Document) {
      final el = node.documentElement;
      if (el == null) return const [];
      scope = el;
    } else if (node is hd.Element) {
      scope = node;
    } else {
      return const [];
    }

    var path = expr.trim();
    // 尾部属性/文本提取
    String? extract;
    final tailRe = RegExp(r'/(@[\w:-]+|text\(\))$');
    final m = tailRe.firstMatch(path);
    if (m != null) {
      extract = m.group(1)!;
      path = path.substring(0, m.start);
    }
    if (attr != null && attr.isNotEmpty && extract == null) {
      extract = '@$attr';
    }

    var steps = _xpathSteps(path);
    if (steps.isEmpty) return const [];

    var cur = <hd.Element>[scope];
    for (final step in steps) {
      final out = <hd.Element>[];
      for (final e in cur) {
        Iterable<hd.Element> children;
        if (step.isDescendant) {
          children = e.querySelectorAll(step.tag);
        } else {
          children = e.children.where((c) => step.tag == '*' || c.localName == step.tag);
        }
        for (final c in children) {
          if (_matchPredicates(c, step.predicates)) out.add(c);
        }
      }
      cur = out;
    }

    if (extract == null) return cur;
    final ex = extract;
    return cur.map((e) => _xpathExtract(e, ex)).toList();
  }

  String _xpathExtract(hd.Element e, String extract) {
    if (extract == 'text()') return e.text.trim();
    final name = extract.substring(1);
    if (name == 'text') return e.text.trim();
    return e.attributes[name] ?? '';
  }

  List<_XPathStep> _xpathSteps(String path) {
    // 先剥掉谓词再按 / 分割，避免 // 被谓词内的 // 干扰（v1 假定谓词内无斜杠）
    final steps = <_XPathStep>[];
    var i = 0;
    final n = path.length;
    while (i < n) {
      var desc = false;
      if (path.startsWith('//', i)) {
        desc = true;
        i += 2;
      } else if (path.startsWith('/', i)) {
        i += 1;
      } else if (i == 0 && path.startsWith('./', i)) {
        i += 2;
      }
      if (i >= n) break;
      // 读 tag
      var j = i;
      while (j < n && path[j] != '/' && path[j] != '[') {
        j++;
      }
      var tag = path.substring(i, j).trim();
      if (tag == '.') {
        i = j;
        continue;
      }
      // 读谓词
      final predicates = <_XPred>[];
      while (j < n && path[j] == '[') {
        var depth = 0;
        var k = j;
        for (; k < n; k++) {
          if (path[k] == '[') depth++;
          if (path[k] == ']') {
            depth--;
            if (depth == 0) break;
          }
        }
        final pred = path.substring(j + 1, k);
        final p = _parsePredicate(pred.trim());
        if (p != null) predicates.add(p);
        j = k + 1;
      }
      steps.add(_XPathStep(tag, desc, predicates));
      i = j;
      // 跳过重复斜杠
      while (i < n && path[i] == '/') {
        if (path.startsWith('//', i)) {
          break; // 下一步循环处理为 descendant
        }
        i++;
      }
    }
    return steps;
  }

  _XPred? _parsePredicate(String pred) {
    // [n]
    final idx = int.tryParse(pred);
    if (idx != null) return _XPred(index: idx);
    // [@attr='v'] / [@attr="v"] / [@attr]
    final am =
        RegExp(r'^@([\w:-]+)(?:\s*=\s*["\x27]([^"\x27]*)["\x27])?$').firstMatch(pred);
    if (am != null) {
      return _XPred(attr: am.group(1)!, value: am.group(2));
    }
    // [@class~='v'] contains-class
    final cm =
        RegExp(r'^@([\w:-]+)\s*~=\s*["\x27]([^"\x27]*)["\x27]$').firstMatch(pred);
    if (cm != null) {
      return _XPred(attr: cm.group(1)!, contains: cm.group(2));
    }
    // contains(@attr,'v')
    final ct = RegExp(
      r'^contains\(\s*@([\w:-]+)\s*,\s*["\x27]([^"\x27]*)["\x27]\s*\)$',
    ).firstMatch(pred);
    if (ct != null) {
      return _XPred(attr: ct.group(1)!, contains: ct.group(2));
    }
    return null;
  }

  bool _matchPredicates(hd.Element e, List<_XPred> preds) {
    for (final p in preds) {
      if (p.attr != null) {
        final v = e.attributes[p.attr!] ?? '';
        if (p.contains != null) {
          if (p.attr == 'class') {
            if (!v.split(RegExp(r'\s+')).contains(p.contains)) return false;
          } else if (!v.contains(p.contains!)) {
            return false;
          }
        } else if (p.value != null && v != p.value) {
          return false;
        } else if (p.value == null && v.isEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  // ---------- JSONPath（子集） ----------

  /// 支持 `a.b.c` `.a[0]` `a[*].b` `a.b|c`（键备选）。
  List<dynamic> _evalJsonPath(dynamic value, String path) {
    var cur = <dynamic>[value];
    final tokens = _jsonTokens(path);
    for (final t in tokens) {
      final next = <dynamic>[];
      for (final v in cur) {
        if (t.all) {
          next.addAll(_jsonAll(v, t));
        } else {
          final r = _jsonGet(v, t);
          if (r != null) next.add(r);
        }
      }
      cur = next;
    }
    return cur;
  }

  List<_JTok> _jsonTokens(String path) {
    final out = <_JTok>[];
    final re = RegExp(r'\.([A-Za-z_][\w-]*)|\[(\*|-?\d+)\]');
    var i = 0;
    // 首段裸键（无前导点）：如 data.list[*]
    final bare = RegExp('^([A-Za-z_][\\w-]*)').firstMatch(path);
    if (bare != null) {
      out.add(_JTok(bare.group(1)!));
      i = bare.end;
    }
    while (i < path.length) {
      final m = re.matchAsPrefix(path, i);
      if (m == null) break;
      if (m.group(1) != null) {
        out.add(_JTok(m.group(1)!));
      } else if (m.group(2) == '*') {
        out.add(_JTok('', all: true));
      } else {
        out.add(_JTok('', index: int.parse(m.group(2)!)));
      }
      i = m.end; // matchAsPrefix 的 end 是绝对索引
    }
    return out;
  }

  dynamic _jsonGet(dynamic v, _JTok t) {
    if (t.index != null) {
      if (v is List && t.index! < v.length) {
        return v[t.index! < 0 ? v.length + t.index! : t.index!];
      }
      return null;
    }
    if (v is Map) return v[t.key];
    return null;
  }

  List<dynamic> _jsonAll(dynamic v, _JTok t) {
    if (v is List) return v;
    if (v is Map) return v.values.toList();
    return const [];
  }

  String _stringify(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is hd.Element || v is hd.Document) return _stringifyNode(v);
    if (v is num || v is bool) return v.toString();
    if (v is List || v is Map) return jsonEncode(v);
    return v.toString();
  }

  /// H-Viewer 语义正则后处理：对每个值做 regex 匹配，replacement 支持 $1..$9。
  List<String> _applyPost(String? regex, String? replacement, List<String> values) {
    if (regex == null || regex.isEmpty) return values;
    final re = RegExp(regex, multiLine: true);
    final rep = replacement ?? '';
    return values.map((v) {
      final m = re.firstMatch(v);
      if (m == null) return v;
      return rep.replaceAllMapped(RegExp(r'\$(\d)'), (g) {
        final idx = int.parse(g.group(1)!);
        return idx <= m.groupCount ? (m.group(idx) ?? '') : '';
      }).replaceAll(r'$0', m.group(0) ?? '');
    }).toList();
  }

  String _stringifyNode(dynamic v) {
    if (v is hd.Document) return v.documentElement?.text.trim() ?? '';
    if (v is hd.Element) return v.text.trim();
    return '';
  }
}

class _XPathStep {
  _XPathStep(this.tag, this.isDescendant, this.predicates);
  final String tag;
  final bool isDescendant;
  final List<_XPred> predicates;
}

class _XPred {
  _XPred({this.index, this.attr, this.value, this.contains});
  final int? index;
  final String? attr;
  final String? value;
  final String? contains;
}

class _JTok {
  _JTok(this.key, {this.index, this.all = false});
  final String key;
  final int? index;
  final bool all;
}
