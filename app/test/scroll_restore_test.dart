import 'package:flutter_test/flutter_test.dart';

import 'package:comic_forge/state/scroll_restore.dart';

void main() {
  group('resolveRestoredScroll 恢复偏移边界', () {
    test('未保存/非正值 → 0', () {
      expect(resolveRestoredScroll(saved: null, maxExtent: 1000), 0);
      expect(resolveRestoredScroll(saved: 0, maxExtent: 1000), 0);
      expect(resolveRestoredScroll(saved: -5, maxExtent: 1000), 0);
    });

    test('范围内正常恢复', () {
      expect(resolveRestoredScroll(saved: 500, maxExtent: 1000), 500);
    });

    test('超出范围 clamp 到 maxExtent（图片渐进加载场景）', () {
      expect(resolveRestoredScroll(saved: 1500, maxExtent: 1000), 1000);
      expect(resolveRestoredScroll(saved: 500, maxExtent: 0), 0,
          reason: '首帧无可滚动范围时回顶，后续帧由用户位置接管');
    });
  });
}
