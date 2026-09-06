import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  group('AdBlockRules', () {
    test('标准格式：urlRules/nameRules 正则过滤', () {
      final r = AdBlockRules.fromJson({
        'enabled': true,
        'urlRules': [r'adserver', r'\.abc\.net/img/'],
        'nameRules': ['预告|插页'],
      });
      expect(r.blocksImageUrl('https://adserver.example.com/1.jpg'), isTrue);
      expect(r.blocksImageUrl('https://img.abc.net/img/2.jpg'), isTrue);
      expect(r.blocksImageUrl('https://img.ok.net/3.jpg'), isFalse);
      expect(r.blocksName('第1话 预告'), isTrue);
      expect(r.blocksName('第2话'), isFalse);
      expect(r.filterImages(['https://img.ok.net/3.jpg', 'https://img.abc.net/img/2.jpg']),
          ['https://img.ok.net/3.jpg']);
    });

    test('别名键 adUrl/adName + 纯数组视为 urlRules', () {
      final r1 = AdBlockRules.fromJson({'adUrl': ['x.com'], 'adName': ['广告']});
      expect(r1.urlRules, hasLength(1));
      expect(r1.nameRules, hasLength(1));
      final r2 = AdBlockRules.tryParse('["a.com","b.com"]');
      expect(r2!.urlRules, hasLength(2));
    });

    test('坏 JSON / 坏正则不抛错', () {
      expect(AdBlockRules.tryParse('{bad json'), isNull);
      final r = AdBlockRules.fromJson({
        'urlRules': ['[unclosed', 'ok.net', 42, '']
      });
      expect(r.urlRules, hasLength(1), reason: '只保留合法正则');
    });

    test('enabled=false 时不拦截', () {
      final r = AdBlockRules.fromJson({'enabled': false, 'urlRules': ['x.com']});
      expect(r.blocksImageUrl('https://x.com/a.jpg'), isFalse);
    });

    test('caseSensitive 默认关闭（大写域名也命中）', () {
      final r = AdBlockRules.fromJson({'urlRules': ['ADSERVER']});
      expect(r.blocksImageUrl('https://adServer.example.com/a.jpg'), isTrue);
    });
  });
}
