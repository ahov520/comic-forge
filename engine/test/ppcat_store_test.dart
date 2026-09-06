import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:engine/src/store/ppcat_store.dart';
import 'package:test/test.dart';

void main() {
  group('PpcatStoreInspector（真实样本回归）', () {
    late List<int> bytes;

    setUpAll(() {
      bytes = File('test/fixtures/ppcat_store_sample.bin').readAsBytesSync();
    });

    test('解析 .mh_rules 中央目录', () {
      final s = PpcatStoreInspector.inspect(bytes);
      expect(s.entry.name, '.mh_rules');
      expect(s.entry.method, 8); // deflate
      expect(s.entry.compressedSize, 205423);
      expect(s.entry.uncompressedSize, 1393919);
      expect(s.entry.crc32, 0xd6a5e51b);
      // 加密区 = 整个 cdOff 之前的部分
      expect(s.encryptedRegion.length, s.entry.encryptedRegionLength);
    });

    test('无解密器时拒绝解密明文调用（结构不合法报错）', () {
      // 乱数据应抛 FormatException 而非崩溃
      expect(
        () => PpcatStoreInspector.inspect([1, 2, 3, 4, 5, 6, 7, 8]),
        throwsFormatException,
      );
    });

    test('明文 ZIP 首条目解压（构造标准 zip 验证 unzipFirstEntryText）', () {
      // 用 archive 造一个明文 zip，验证我们的解压辅助正确
      final encoder = ZipEncoder();
      final data = utf8.encode('{"hello":"漫画"}');
      final arch = Archive()
        ..addFile(ArchiveFile('demo.json', data.length, data));
      final zipBytes = encoder.encode(arch);
      final text = PpcatStoreInspector.unzipFirstEntryText(zipBytes);
      expect(text, '{"hello":"漫画"}');
    });
  });
}
