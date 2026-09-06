import 'package:engine/src/analyzer/rule_analyzer.dart';
import 'package:test/test.dart';

void main() {
  group('RuleAnalyzer', () {
    test('CSS 管道 + 属性提取', () {
      final r = RuleAnalyzer('div.item@tag.a@text').parse();
      expect(r.branches.length, 1);
      expect(r.branches[0].length, 1); // 单管道
      final pipe = r.branches[0][0];
      expect(pipe[0].type, 'css');
      expect(pipe[0].value, 'div.item');
      expect(pipe[1].type, 'shorthand'); // tag.a 是简写
      expect(pipe[1].attr, 'text');
    });

    test('@css: 前缀', () {
      final r = RuleAnalyzer('@css:.title@text').parse();
      expect(r.branches[0][0][0].type, 'css');
      expect(r.branches[0][0][0].value, '.title');
      expect(r.branches[0][0][0].attr, 'text');
    });

    test('XPath 直通', () {
      final r = RuleAnalyzer('//div[@class="item"]/a/@href').parse();
      final seg = r.branches[0][0][0];
      expect(seg.type, 'xpath');
      expect(seg.value, '//div[@class="item"]/a/@href');
    });

    test('JSONPath 直通', () {
      final r = RuleAnalyzer(r'$.data.list[*].name').parse();
      final seg = r.branches[0][0][0];
      expect(seg.type, 'json');
      expect(seg.value, 'data.list[*].name');
    });

    test('|| 备选分支', () {
      final r = RuleAnalyzer('.a@text || .b@text').parse();
      expect(r.branches.length, 2);
    });

    test('&& 合并组', () {
      final r = RuleAnalyzer('.a@text && .b@text').parse();
      expect(r.branches[0].length, 2);
    });

    test('引号内分隔符不拆分', () {
      final r = RuleAnalyzer(r'''a[title="x||y"]@text''').parse();
      expect(r.branches.length, 1);
    });

    test('单独 @text 作用于当前节点', () {
      final r = RuleAnalyzer('@text').parse();
      final seg = r.branches[0][0][0];
      expect(seg.type, 'self');
      expect(seg.attr, 'text');
    });

    test('URL 模板渲染', () {
      final url = renderUrlTemplate(
          'https://m.example.com/search?q={{key}}&p={{page}}',
          {'key': '%E6%B5%B7%E8%B4%BC', 'page': '2'});
      expect(url, 'https://m.example.com/search?q=%E6%B5%B7%E8%B4%BC&p=2');
    });
  });
}
