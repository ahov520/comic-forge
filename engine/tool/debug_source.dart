// 调试"0条"源：抓响应 + 应用列表规则，显示节点数与样例。
// 用法：dart run tool/debug_source.dart <源名关键词> [关键词]
import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:html/parser.dart' as hp;

Future<void> main(List<String> args) async {
  final needle = args.isNotEmpty ? args[0] : '快看';
  final keyword = args.length > 1 ? args[1] : '斗罗大陆';
  final j = jsonDecode(File('../app/assets/store.json').readAsStringSync())
      as Map<String, dynamic>;
  final sources = (j['sources'] as List)
      .whereType<Map<String, dynamic>>()
      .map(ComicSource.fromPpcatFlat)
      .toList();
  final src = sources.firstWhere((s) => s.name.contains(needle));
  print('== ${src.name}  ${src.url}');
  print('searchUrl: ${src.rules.searchUrl}');
  print('searchList: ${src.rules.searchList}');
  print('searchName: ${src.rules.searchName}');
  print('bookUrl: ${src.rules.searchBookUrl}');

  final key = Uri.encodeComponent(keyword);
  final req = parseRuleUrl(renderUrlTemplate(src.rules.searchUrl,
      {'key': key, 'searchKey': key, 'searchPage': '1', 'page': '1', 'pageSize': '20'}));
  final abs = Uri.parse(src.url).resolve(req.url).toString();
  print('METHOD: ${req.method}  $abs');
  if (req.body.isNotEmpty) print('body: ${req.body}');
  final bytes = await HttpFetcher()
      .send(SourceRequest(url: abs, method: req.method, body: req.body, headers: req.headers));
  final text = utf8.decode(bytes, allowMalformed: true);
  print('响应前400字: ${text.substring(0, text.length < 400 ? text.length : 400)}');

  dynamic doc;
  final t = text.trimLeft();
  if (t.startsWith('{') || t.startsWith('[')) {
    doc = jsonDecode(text);
    print('(JSON)');
  } else {
    doc = hp.parse(text);
    print('(HTML)');
  }
  final eval = const RuleEvaluator();
  final rule = RuleAnalyzer(src.rules.searchList).parse();
  final nodes = eval.evalNodes(doc, rule);
  print('列表节点数: ${nodes.length}');
  if (nodes.isNotEmpty && src.rules.searchName.isNotEmpty) {
    final name =
        eval.evalFirst(nodes.first, RuleAnalyzer(src.rules.searchName).parse());
    print('首条名: $name');
  }
}
