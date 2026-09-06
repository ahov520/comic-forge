/// ppcat `.mh_rules` 加密 ZIP 的结构层（侦查已确认的布局）：
///
/// ```text
/// [0 .. cdOff)                加密区：本地文件头(LFH) + deflate 压缩数据
/// [cdOff .. cdOff+cdSize)     明文 ZIP 中央目录（单个 entry：.mh_rules）
/// [cdOff+cdSize .. )          EOCD（部分字段可能被污染）
/// ```
///
/// 解密算法未知（流式密码、逐文件密钥流不同），由 [StoreDecryptor] 注入——
/// Phase 0 取证成功后提供实现。
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'tolerant_inflate.dart';

/// 从字节流解析出的加密 ZIP 元信息。
class PpcatZipEntry {
  PpcatZipEntry({
    required this.name,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.encryptedRegionLength,
    required this.centralDirectoryOffset,
  });

  final String name;
  final int method; // 8 = deflate
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;

  /// 加密区长度 = cdOff（LFH+数据整段）。
  final int encryptedRegionLength;
  final int centralDirectoryOffset;

  static const int signatureCdh = 0x02014b50;
}

/// 解析结果：entry 元信息 + 加密区字节。
class PpcatStoreStructure {
  PpcatStoreStructure({required this.entry, required this.encryptedRegion, required this.raw});

  final PpcatZipEntry entry;
  final List<int> encryptedRegion;
  final List<int> raw;
}

/// 解密器接口：拿到明文（应为标准 ZIP：LFH + 数据 + CD + EOCD）。
typedef StoreDecryptor = List<int> Function(PpcatStoreStructure structure);

/// 结构检查/解密入口。
class PpcatStoreInspector {
  /// 解析 `.mh_rules` 加密包结构。数据不合法时抛 [FormatException]。
  static PpcatStoreStructure inspect(List<int> bytes) {
    final raw = bytes;
    final cdhIdx = _lastIndex(raw, PpcatZipEntry.signatureCdh);
    if (cdhIdx < 0) {
      throw const FormatException('未找到 ZIP 中央目录签名（不是 .mh_rules 结构）');
    }
    final cdh = raw.sublist(cdhIdx);
    if (cdh.length < 46) throw const FormatException('中央目录过短');

    int u16(int off) => cdh[off] | (cdh[off + 1] << 8);
    int u32(int off) =>
        cdh[off] | (cdh[off + 1] << 8) | (cdh[off + 2] << 16) | (cdh[off + 3] << 24);

    final nameLen = u16(28);
    final name = latin1.decode(cdh.sublist(46, 46 + nameLen), allowInvalid: true);

    final entry = PpcatZipEntry(
      name: name,
      method: u16(10),
      crc32: u32(16),
      compressedSize: u32(20),
      uncompressedSize: u32(24),
      encryptedRegionLength: cdhIdx,
      centralDirectoryOffset: cdhIdx,
    );
    return PpcatStoreStructure(
      entry: entry,
      encryptedRegion: raw.sublist(0, cdhIdx),
      raw: raw,
    );
  }

  /// 用注入的解密器解出明文 ZIP 字节。
  static List<int> decrypt(PpcatStoreStructure s, StoreDecryptor decryptor) =>
      decryptor(s);

  /// 便捷：解密后解压 ZIP 内第一个 entry 并按 UTF-8 文本返回。
  static String unzipFirstEntryText(List<int> plainZip) {
    final archive = ZipDecoder().decodeBytes(plainZip);
    if (archive.isEmpty) throw const FormatException('明文 ZIP 内无文件');
    final content = archive.first.content as List<int>;
    return utf8.decode(content, allowMalformed: true);
  }

  /// 无密钥部分提取：`.mh_rules` 的写入方把 deflate 流的**前缀**以明文
  /// 形式留在 EOCD 之后（`[加密区][明文CDH][EOCD][LFH尾片段+明文deflate]`），
  /// 加密区只含流的**后缀**。本方法解出明文分片 → 源 JSON 前缀（可能截断）。
  ///
  /// 返回 null 表示该文件无明文分片（加密布局不同或数据损坏）。
  static String? partialJson(List<int> bytes) {
    final sig = [0x50, 0x4b, 0x05, 0x06]; // PK\x05\x06
    var eocd = -1;
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == sig[0] && bytes[i + 1] == sig[1] && bytes[i + 2] == sig[2] && bytes[i + 3] == sig[3]) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;
    final tail = bytes.sublist(eocd + 22);
    // deflate 起点 = 尾部最后一个 `.mh_rules` 名字之后
    final nameSig = utf8.encode('.mh_rules');
    var frag = -1;
    for (var i = tail.length - nameSig.length; i >= 0; i--) {
      var ok = true;
      for (var j = 0; j < nameSig.length; j++) {
        if (tail[i + j] != nameSig[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        frag = i;
        break;
      }
    }
    if (frag < 0) return null;
    final start = frag + nameSig.length;
    if (start >= tail.length) return null;
    final s = inflateTextTolerant(tail.sublist(start));
    if (s == null) return null;
    if (s.contains('bookSource') || s.contains('ruleSearch')) return s;
    return null;
  }

  static int _lastIndex(List<int> hay, int u32sig) {
    final b = [u32sig & 0xff, (u32sig >> 8) & 0xff, (u32sig >> 16) & 0xff, (u32sig >> 24) & 0xff];
    for (var i = hay.length - 4; i >= 0; i--) {
      if (hay[i] == b[0] &&
          hay[i + 1] == b[1] &&
          hay[i + 2] == b[2] &&
          hay[i + 3] == b[3]) {
        return i;
      }
    }
    return -1;
  }
}
