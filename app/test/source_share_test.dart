import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/clipboard_import.dart';
import 'package:comic_forge/state/source_share.dart';

void main() {
  group('sourceShareJson', () {
    test('ppcat 源：原始平铺 JSON 保真输出', () {
      final s = ComicSource.fromPpcatFlat({
        'bookSourceName': '腾讯漫画',
        'bookSourceUrl': 'https://m.ac.qq.com',
        'ruleSearchUrl': '/search?word=searchKey',
      });
      final out = sourceShareJson(s);
      expect(out, contains('"bookSourceName"'));
      expect(out, contains('腾讯漫画'));
      expect(out, isNot(contains('failCount')), reason: '原始 JSON 无健康噪音');
    });

    test('手建源（raw 为空）：嵌套 toJson 且剥离健康字段', () {
      final s = ComicSource(
        id: 'https://m.example.com',
        name: '手建源',
        url: 'https://m.example.com',
      );
      s.rules.searchUrl = '/s?q={{key}}';
      s.failCount = 5;
      s.lastError = 'HTTP 404';
      final out = sourceShareJson(s);
      expect(out, contains('"name"'));
      expect(out, isNot(contains('failCount')));
      expect(out, isNot(contains('lastError')));
    });

    test('闭环：分享产物可经剪贴板导入还原同名同源', () {
      final s = ComicSource.fromPpcatFlat({
        'bookSourceName': '闭环源',
        'bookSourceUrl': 'https://m.example.com/loop',
        'ruleSearchUrl': '/search?word=searchKey',
      });
      final out = sourceShareJson(s);
      final r = ClipboardSourceImport.parse(out);
      expect(r, isA<ClipboardImportSingle>());
      final back = (r as ClipboardImportSingle).source;
      expect(back.name, '闭环源');
      expect(back.rules.searchUrl, contains('searchKey'));
    });
  });
}
