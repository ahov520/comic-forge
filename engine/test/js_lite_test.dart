import 'package:engine/src/analyzer/js_lite.dart';
import 'package:test/test.dart';

void main() {
  group('evalJsLite', () {
    test('B站列表块：静态默认值 + if 块移除 + 不可求值 var 跳过', () {
      const js = '''
var json=JSON.parse(result);
var out='\$.data.list.*|\$.data.*';
if(json.data.list&&json.data.list.length==0){
out=undefined;
}
out
''';
      expect(evalJsLite(js), r'$.data.list.*|$.data.*');
    });

    test('result 字符串拼接（B站 detail URL 模板）', () {
      const js = '''
'https://manga.bilibili.com/twirp/comic.v1.Comic/ComicDetail?device=h5&platform=h5@{"comic_id":'+result+'}@PostJson'
''';
      expect(
          evalJsLite(js, result: '30956'),
          'https://manga.bilibili.com/twirp/comic.v1.Comic/ComicDetail'
          '?device=h5&platform=h5@{"comic_id":30956}@PostJson');
    });

    test('多段拼接 + 数字字面量', () {
      expect(evalJsLite(r"'a'+result+'b'+1", result: 'X'), 'aXb1');
    });

    test('java.ajax 等未知依赖 → null', () {
      expect(evalJsLite("java.ajax('https://x/y')"), isNull);
    });

    test('无 result 时依赖 result 的拼接 → null', () {
      expect(evalJsLite(r"'a'+result"), isNull);
    });

    test('注释剥离', () {
      const js = r'''
// comment
var out='$.a';
out // tail''';
      expect(evalJsLite(js), r'$.a');
    });

    test('URL 中的 // 不被当注释', () {
      expect(
          evalJsLite(r"'https://x.com/a'+result", result: '1'),
          'https://x.com/a1');
    });
  });

  group('normalizeJsonPathLiteral', () {
    test(r'$.a.b.*|$.c → $.a.b[*]||$.c[*]', () {
      expect(normalizeJsonPathLiteral(r'$.data.list.*|$.data.*'),
          r'$.data.list[*]||$.data[*]');
    });

    test('非 jsonpath 字面量原样返回', () {
      expect(normalizeJsonPathLiteral('https://x.com'), 'https://x.com');
    });
  });
}
