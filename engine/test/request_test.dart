import 'package:engine/src/analyzer/rule_analyzer.dart';
import 'package:engine/src/net/request.dart';
import 'package:test/test.dart';

void main() {
  group('parseRuleUrl（ppcat @ 语法）', () {
    test('纯 URL → GET', () {
      final r = parseRuleUrl('https://m.example.com/search?q=searchKey');
      expect(r.method, 'GET');
      expect(r.isPost, isFalse);
      expect(r.url, 'https://m.example.com/search?q=searchKey');
      expect(r.body, '');
    });

    test('url@k=v&k2=v2 → POST form', () {
      final r = parseRuleUrl(
          'https://m.example.com/api/search@page=searchPage&key=searchKey');
      expect(r.isPost, isTrue);
      expect(r.body, 'page=searchPage&key=searchKey');
      expect(r.headers['Content-Type'], 'application/x-www-form-urlencoded');
    });

    test('url@{json}@PostJson → POST JSON（B站 twirp 风格）', () {
      final r = parseRuleUrl(
          'https://manga.bilibili.com/twirp/comic.v1.Comic/Search'
          '@{"platform":"h5","key_word":"searchKey","page_num":1}'
          '@Header:{"Content-Type":"application/json;charset=UTF-8"}@PostJson');
      expect(r.isPost, isTrue);
      expect(r.body, contains('"key_word":"searchKey"'));
      expect(r.headers['Content-Type'], contains('application/json'));
    });

    test('@Header: 宽容解析（无引号键 / 单引号值 / GET 保持）', () {
      final r = parseRuleUrl(
          '/search?title=searchKey&page=searchPage@Header:{Cookie:"mangabz_lang=2"}');
      expect(r.method, 'GET');
      expect(r.headers['Cookie'], 'mangabz_lang=2');

      final r2 = parseRuleUrl('/x@Header:{x-requested-with: XMLHttpRequest}');
      expect(r2.headers['x-requested-with'], 'XMLHttpRequest');
    });

    test('引号/花括号内的 @ 不拆分；Header 里带 = 值不被误当表单体', () {
      final r = parseRuleUrl(
          'https://h.example.com/p@{"sign":"a@b","t":1}@Header:{"Authorization":"Bearer a@b=c"}@PostJson');
      expect(r.isPost, isTrue);
      expect(r.body, '{"sign":"a@b","t":1}');
      expect(r.headers['Authorization'], 'Bearer a@b=c');
    });

    test('PostJson 标记在前也接受（位置不限）', () {
      final r = parseRuleUrl('https://h.example.com/api@PostJson@{"a":1}');
      expect(r.isPost, isTrue);
      expect(r.body, '{"a":1}');
    });
  });

  group('renderUrlTemplate 数值算术偏移', () {
    test('searchPage-1 / page+1', () {
      expect(
          renderUrlTemplate('/api?k=searchKey&page=searchPage-1',
              {'key': 'x', 'searchPage': '3'}),
          '/api?k=x&page=2');
      expect(
          renderUrlTemplate('/api?page={page+1}', {'page': '4'}),
          '/api?page=5');
    });

    test('非数值变量不做算术（搜索词不被破坏）', () {
      expect(
          renderUrlTemplate('/api?w=searchKey-1', {'key': '海贼王'}),
          '/api?w=海贼王-1');
    });

    test('pageSize 算术与其他变量', () {
      expect(
          renderUrlTemplate('/api?n=pageSize-10', {'pageSize': '30'}),
          '/api?n=20');
    });

    test('{{}} 内算术表达式求值（快看 48*(searchPage-1) 风格）', () {
      expect(
          renderUrlTemplate('/v1/search?q=searchKey&since={{48*(searchPage-1)}}',
              {'key': 'x', 'searchPage': '1'}),
          '/v1/search?q=x&since=0');
      expect(
          renderUrlTemplate('/v1/search?since={{48*(searchPage-1)}}',
              {'searchPage': '3'}),
          '/v1/search?since=96');
      expect(
          renderUrlTemplate('/api?o={{searchPage+2}}', {'searchPage': '5'}),
          '/api?o=7');
    });

    test('evalArithmetic 边界（除零/残缺表达式返回 null）', () {
      expect(evalArithmetic('48*(3-1)'), '96');
      expect(evalArithmetic('2-3'), '-1');
      expect(evalArithmetic('10/0'), isNull);
      expect(evalArithmetic('48*('), isNull);
      expect(evalArithmetic('abc'), isNull);
    });
  });
}
