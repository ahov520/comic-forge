import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  group('TolerantInflater', () {
    test('完整流正常解压', () {
      final data = utf8.encode('{"hello":"漫画世界","n":123}');
      final comp = ZLibEncoder().encode(data);
      // 去掉 zlib 头尾得到 raw deflate
      final raw = comp.sublist(2, comp.length - 4);
      final out = TolerantInflater.inflateTolerant(raw);
      expect(utf8.decode(out), '{"hello":"漫画世界","n":123}');
    });

    test('截断流返回已解出前缀而不抛异常', () {
      final data = utf8.encode('A' * 100000);
      final comp = ZLibEncoder().encode(data);
      final raw = comp.sublist(2, comp.length - 4);
      final out = TolerantInflater.inflateTolerant(raw.sublist(0, raw.length ~/ 2));
      expect(out.length, greaterThan(100));
      expect(out.every((b) => b == 65), isTrue);
    });
  });

  group('partialJson（真实大store回归）', () {
    late List<int> bytes;

    setUpAll(() {
      bytes = File('test/fixtures/ppcat_store_sample.bin').readAsBytesSync();
    });

    test('解出明文分片 JSON 前缀', () {
      final s = PpcatStoreInspector.partialJson(bytes)!;
      expect(s, startsWith('[{"bookSourceName":"腾讯漫画（正版）"'));
      // 与 Python 参考实现的输出长度一致（735214B）
      expect(utf8.encode(s).length, 735214);
    });

    test('明文分片可抽出 190+ 完整源', () {
      // 经由 RepoClient 的条目提取逻辑（私有，这里用 SharedRule 验证同一条链路）
      final rule = SharedRule(name: 'x', storeBytes: bytes);
      final partial = rule.partialRulesJson()!;
      expect(partial.countBookSourceNames(), greaterThanOrEqualTo(190));
    });
  });
}

extension on String {
  int countBookSourceNames() => '"bookSourceName"'.allMatches(this).length;
}
