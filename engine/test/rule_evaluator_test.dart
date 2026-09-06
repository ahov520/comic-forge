import 'dart:convert';

import 'package:engine/src/analyzer/rule_analyzer.dart';
import 'package:engine/src/analyzer/rule_evaluator.dart';
import 'package:html/parser.dart' as hp;
import 'package:test/test.dart';

const htmlDoc = '''
<html><body>
  <div class="list">
    <div class="item">
      <a class="title" href="/comic/1">海贼王</a>
      <span class="author">尾田荣一郎</span>
      <img class="cover" src="/img/one-piece.jpg"/>
      <p class="intro">热血少年漫</p>
    </div>
    <div class="item">
      <a class="title" href="/comic/2">火影忍者</a>
      <span class="author">岸本齐史</span>
      <img class="cover" src="/img/naruto.jpg"/>
      <p class="intro">忍者题材</p>
    </div>
  </div>
  <div id="main">
    <p>段落一</p><p>段落二</p>
  </div>
</body></html>
''';

void main() {
  final eval = const RuleEvaluator();
  final doc = hp.parse(htmlDoc);

  Rule rule(String s) => RuleAnalyzer(s).parse();

  group('CSS / 简写求值', () {
    test('列表选择 + 子字段（列表步用 evalNodes 保留节点）', () {
      final items = eval.evalNodes(doc, rule('.item'));
      expect(items.length, 2);
      final names = eval.eval(items.first, rule('.title@text'));
      expect(names, ['海贼王']);
      final hrefs = eval.eval(items.first, rule('a.title@href'));
      expect(hrefs, ['/comic/1']);
      final covers = eval.eval(items.first, rule('img@src'));
      expect(covers, ['/img/one-piece.jpg']);
    });

    test('多级 @ 管道一步到位', () {
      final r = eval.eval(doc, rule('class.item@class.title@text'));
      expect(r, ['海贼王', '火影忍者']);
    });

    test('id 简写', () {
      final r = eval.eval(doc, rule('id.main@tag.p@text'));
      expect(r, ['段落一', '段落二']);
    });

    test('|| 备选：第一个非空生效', () {
      final r = eval.eval(doc, rule('.nope@text || a.title@text'));
      expect(r, ['海贼王', '火影忍者']);
    });

    test('&& 合并结果', () {
      final r = eval.eval(doc, rule('.author@text && .intro@text'));
      expect(r, ['尾田荣一郎', '岸本齐史', '热血少年漫', '忍者题材']);
    });

    test('attr: 自定义属性', () {
      final r = eval.eval(doc, rule('a.title@attr:href'));
      expect(r.first, '/comic/1');
    });
  });

  group('XPath 子集求值', () {
    test('//tag + /@attr', () {
      final r = eval.eval(doc, rule('//a[@class="title"]/@href'));
      expect(r, ['/comic/1', '/comic/2']);
    });

    test('层级 + 谓词', () {
      final r = eval.eval(doc, rule('//div[@class="item"]/span[@class="author"]/text()'));
      expect(r, ['尾田荣一郎', '岸本齐史']);
    });

    test('contains 谓词', () {
      final r = eval.eval(doc, rule(r'//span[contains(@class,"author")]/text()'));
      expect(r, ['尾田荣一郎', '岸本齐史']);
    });
  });

  group('JSONPath 子集求值', () {
    final json = jsonDecode('''
      {"data":{"list":[
        {"name":"A","images":["a1.jpg","a2.jpg"]},
        {"name":"B","images":["b1.jpg"]}
      ]}}
    ''');

    test('点路径 + 数组下标', () {
      final r = eval.eval(json, rule(r'$.data.list[0].name'));
      expect(r, ['A']);
    });

    test('[*] 展开', () {
      final r = eval.eval(json, rule(r'$.data.list[*].name'));
      expect(r, ['A', 'B']);
    });

    test('嵌套数组', () {
      final r = eval.eval(json, rule(r'$.data.list[1].images[0]'));
      expect(r, ['b1.jpg']);
    });
  });
}
