import 'dart:convert';
import 'dart:typed_data';

/// 容错的 raw-deflate 解压器。
///
/// 标准 inflate 语义 + 容错扩展：输入被截断（流不完整）时不抛异常，
/// 返回已解出的全部输出——用于解 `.mh_rules` 的明文分片（写入方把
/// deflate 流的后半段加密在文件头部，尾部明文分片天然不完整）。
class TolerantInflater {
  TolerantInflater._(this._data);

  final Uint8List _data;
  int _bitPos = 0;
  final List<int> _buf = <int>[];

  int get _outLen => _buf.length;

  int _byteAt(int i) => _buf[i];

  void _emitByte(int b, int maxOutput) {
    if (_buf.length >= maxOutput) throw _Corrupt();
    _buf.add(b);
  }

  void _emitBytes(List<int> bytes, int maxOutput) {
    if (_buf.length + bytes.length > maxOutput) throw _Corrupt();
    _buf.addAll(bytes);
  }

  /// 解压 raw deflate；[maxOutput] 限制输出防止解压炸弹。
  /// 返回已解出的字节（可能不完整）。
  static Uint8List inflateTolerant(List<int> input, {int maxOutput = 64 << 20}) {
    final inf = TolerantInflater._(Uint8List.fromList(input));
    try {
      inf._inflate(maxOutput);
    } on _Truncated {
      // 容错：截断即停止
    } on _Corrupt {
      // 容错：坏块即停止
    }
    return Uint8List.fromList(inf._buf);
  }

  // ---------- 位读取 ----------

  int _readBits(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final byteIdx = _bitPos >> 3;
      if (byteIdx >= _data.length) throw _Truncated();
      final bit = (_data[byteIdx] >> (_bitPos & 7)) & 1;
      v |= bit << i;
      _bitPos++;
    }
    return v;
  }

  // ---------- Huffman ----------

  (List<int>, List<int>) _buildHuff(List<int> lengths) {
    final counts = List<int>.filled(16, 0);
    for (final l in lengths) {
      if (l > 15) throw _Corrupt();
      counts[l]++;
    }
    counts[0] = 0;
    final offs = List<int>.filled(16, 0);
    for (var i = 1; i < 16; i++) {
      offs[i] = offs[i - 1] + counts[i - 1];
    }
    final symCount = lengths.where((l) => l > 0).length;
    final symbols = List<int>.filled(symCount, 0);
    for (var sym = 0; sym < lengths.length; sym++) {
      if (lengths[sym] > 0) {
        symbols[offs[lengths[sym]]++] = sym;
      }
    }
    return (counts, symbols);
  }

  int _decodeSym(List<int> counts, List<int> symbols) {
    var code = 0, first = 0, index = 0;
    for (var len = 1; len < 16; len++) {
      code |= _readBits(1);
      final count = counts[len];
      if (code - first < count) {
        return symbols[index + (code - first)];
      }
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw _Corrupt();
  }

  // ---------- 主循环 ----------

  static const _lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  static const _lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  static const _distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
  static const _distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

  void _inflate(int maxOutput) {
    final fixedLit = List<int>.generate(288, (i) {
      if (i < 144) return 8;
      if (i < 256) return 9;
      if (i < 280) return 7;
      return 8;
    });
    final fixedDist = List<int>.filled(30, 5);

    var bfinal = 0;
    blockLoop:
    do {
      bfinal = _readBits(1);
      final btype = _readBits(2);
      List<int> litCounts, litSyms, distCounts, distSyms;
      if (btype == 0) {
        // stored：对齐字节 → LEN/NLEN → 原样拷贝
        _bitPos = (_bitPos + 7) & ~7;
        final byteIdx = _bitPos >> 3;
        if (byteIdx + 4 > _data.length) throw _Truncated();
        final len = _data[byteIdx] | (_data[byteIdx + 1] << 8);
        final nlen = _data[byteIdx + 2] | (_data[byteIdx + 3] << 8);
        if ((len ^ 0xFFFF) != nlen) throw _Corrupt();
        _bitPos += 32;
        if (byteIdx + 4 + len > _data.length) throw _Truncated();
        _emitBytes(_data.sublist(byteIdx + 4, byteIdx + 4 + len), maxOutput);
        continue blockLoop;
      } else if (btype == 1) {
        (litCounts, litSyms) = _buildHuff(fixedLit);
        (distCounts, distSyms) = _buildHuff(fixedDist);
      } else if (btype == 2) {
        final hlit = _readBits(5) + 257;
        final hdist = _readBits(5) + 1;
        final hclen = _readBits(4) + 4;
        const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        final clLengths = List<int>.filled(19, 0);
        for (var i = 0; i < hclen; i++) {
          clLengths[order[i]] = _readBits(3);
        }
        final (clCounts, clSyms) = _buildHuff(clLengths);
        final lengths = <int>[];
        while (lengths.length < hlit + hdist) {
          final sym = _decodeSym(clCounts, clSyms);
          if (sym < 16) {
            lengths.add(sym);
          } else if (sym == 16) {
            if (lengths.isEmpty) throw _Corrupt();
            final prev = lengths.last;
            final rep = 3 + _readBits(2);
            for (var i = 0; i < rep; i++) {
              lengths.add(prev);
            }
          } else if (sym == 17) {
            final rep = 3 + _readBits(3);
            for (var i = 0; i < rep; i++) {
              lengths.add(0);
            }
          } else {
            final rep = 11 + _readBits(7);
            for (var i = 0; i < rep; i++) {
              lengths.add(0);
            }
          }
        }
        if (lengths.length > hlit + hdist) {
          lengths.removeRange(hlit + hdist, lengths.length);
        }
        (litCounts, litSyms) = _buildHuff(lengths.sublist(0, hlit));
        (distCounts, distSyms) = _buildHuff(lengths.sublist(hlit));
      } else {
        throw _Corrupt();
      }

      while (true) {
        final sym = _decodeSym(litCounts, litSyms);
        if (sym < 256) {
          _emitByte(sym, maxOutput);
        } else if (sym == 256) {
          break;
        } else {
          final li = sym - 257;
          if (li >= _lenBase.length) throw _Corrupt();
          final len = _lenBase[li] + _readBits(_lenExtra[li]);
          final dsym = _decodeSym(distCounts, distSyms);
          if (dsym >= _distBase.length) throw _Corrupt();
          final dist = _distBase[dsym] + _readBits(_distExtra[dsym]);
          if (dist > _outLen) throw _Corrupt();
          for (var i = 0; i < len; i++) {
            _emitByte(_byteAt(_outLen - dist), maxOutput);
          }
        }
      }
    } while (bfinal == 0);
  }
}

class _Truncated implements Exception {}

class _Corrupt implements Exception {}

/// 便捷：解出 UTF-8 文本（容错截断）。
String? inflateTextTolerant(List<int> input, {int maxOutput = 64 << 20}) {
  final out = TolerantInflater.inflateTolerant(input, maxOutput: maxOutput);
  if (out.isEmpty) return null;
  return utf8.decode(out, allowMalformed: true);
}
