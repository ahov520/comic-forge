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

    test('hosts 文本：0.0.0.0 / 127.0.0.1 / 注释 / 空行', () {
      const txt = '''
# 广告域名列表
127.0.0.1 adhost.example.com

0.0.0.0 tracker.example.net
! 注释行
''';
      final r = AdBlockRules.tryParse(txt)!;
      expect(r.urlRules, hasLength(2));
      expect(r.blocksImageUrl('https://adhost.example.com/pic/1.jpg'), isTrue);
      expect(r.blocksImageUrl('https://sub.tracker.example.net/2.jpg'), isTrue,
          reason: '域名规则应命中子域');
      expect(r.blocksImageUrl('https://ok.example.com/3.jpg'), isFalse);
    });

    test('adblock 语法：||domain^ 提取域名，@@ 白名单跳过', () {
      const txt = '''
||ads.example.com^
||cdn.tracker.io^/bad/
@@||allow.example.com^
''';
      final r = AdBlockRules.tryParse(txt)!;
      expect(r.urlRules, hasLength(2));
      expect(r.blocksImageUrl('https://ads.example.com/a/1.jpg'), isTrue);
      expect(r.blocksImageUrl('https://x.cdn.tracker.io/bad/2.jpg'), isTrue);
      expect(r.blocksImageUrl('https://allow.example.com/3.jpg'), isFalse);
    });

    test('JSON 键别名 adList/urls/blockUrls 均可', () {
      expect(AdBlockRules.fromJson({'adList': ['a.com']}).urlRules, hasLength(1));
      expect(AdBlockRules.fromJson({'urls': ['b.com']}).urlRules, hasLength(1));
      expect(AdBlockRules.fromJson({'blockUrls': ['c.com']}).urlRules, hasLength(1));
      expect(AdBlockRules.fromJson({'nameList': ['广告']}).nameRules, hasLength(1));
    });

    test('生态格式族总结：ppcat 风格 URL 正则数组 + enabled 开关共存', () {
      const txt = '{"enabled":true,"adUrl":["(?i)adimg","cdn.pop"]}';
      final r = AdBlockRules.tryParse(txt)!;
      expect(r.enabled, isTrue);
      expect(r.blocksImageUrl('https://CDN.POP.example.com/x.jpg'), isTrue);
    });
  });
}
