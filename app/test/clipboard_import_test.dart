import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/clipboard_import.dart';

void main() {
  group('ClipboardSourceImport.parse', () {
    test('单条 ppcat 平铺 → Single（规则落位）', () {
      const j = '''
{"bookSourceName":"腾讯漫画","bookSourceUrl":"https://m.ac.qq.com",
 "ruleSearchUrl":"/search?word=searchKey","ruleSearchList":"class.item"}''';
      final r = ClipboardSourceImport.parse(j);
      expect(r, isA<ClipboardImportSingle>());
      final s = (r as ClipboardImportSingle).source;
      expect(s.name, '腾讯漫画');
      expect(s.rules.searchUrl, contains('searchKey'));
    });

    test('单条嵌套 rules → Single', () {
      const j = '''
{"name":"甲","url":"https://m.example.com",
 "rules":{"searchUrl":"/s?q={{key}}","searchList":".item"}}''';
      final r = ClipboardSourceImport.parse(j);
      final s = (r as ClipboardImportSingle).source;
      expect(s.rules.searchUrl, '/s?q={{key}}');
    });

    test('数组多条 → Many（跳过不可解析条目）', () {
      const j = '''
[{"bookSourceName":"甲","bookSourceUrl":"https://a.example.com","ruleSearchUrl":"/s"},
 {"bad":true},
 {"name":"乙","url":"https://b.example.com","rules":{"searchUrl":"/x"}}]''';
      final r = ClipboardSourceImport.parse(j);
      expect(r, isA<ClipboardImportMany>());
      expect((r as ClipboardImportMany).sources.map((s) => s.name), ['甲', '乙']);
    });

    test('坏 JSON / 空文本 / 非源结构 → Invalid 带原因', () {
      expect((ClipboardSourceImport.parse('') as ClipboardImportInvalid).message,
          contains('剪贴板为空'));
      expect((ClipboardSourceImport.parse('{bad') as ClipboardImportInvalid).message,
          contains('JSON'));
      expect(
          (ClipboardSourceImport.parse('{"foo":1}') as ClipboardImportInvalid)
              .message,
          contains('未找到可识别的源'));
      expect(
          (ClipboardSourceImport.parse('"just a string"') as ClipboardImportInvalid)
              .message,
          contains('结构'));
    });

    test('与编辑器/持久化互通：解析结果可 toJson 往返', () {
      const j =
          '{"bookSourceName":"往返","bookSourceUrl":"https://m.example.com","ruleSearchUrl":"/s"}';
      final s = (ClipboardSourceImport.parse(j) as ClipboardImportSingle).source;
      final back = ComicSource.fromJson(s.toJson());
      expect(back.name, '往返');
      expect(back.rules.searchUrl, '/s');
    });
  });
}
