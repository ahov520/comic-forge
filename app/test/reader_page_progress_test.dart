import 'package:comic_forge/state/reader_page_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pageProgressLabel 为 1-based，空列表为空串', () {
    expect(pageProgressLabel(0, 0), '');
    expect(pageProgressLabel(0, 1), '1/1');
    expect(pageProgressLabel(2, 20), '3/20');
    expect(pageProgressLabel(-1, 5), '1/5');
    expect(pageProgressLabel(99, 5), '5/5');
  });

  test('pageProgressFraction 覆盖起止与单页', () {
    expect(pageProgressFraction(0, 0), 0);
    expect(pageProgressFraction(0, 1), 1);
    expect(pageProgressFraction(0, 5), 0);
    expect(pageProgressFraction(2, 5), 0.5);
    expect(pageProgressFraction(4, 5), 1);
  });

  test('滚动偏移与页码互逆，边界不越界', () {
    expect(pageIndexFromScroll(offset: 0, maxExtent: 1000, pageCount: 5), 0);
    expect(pageIndexFromScroll(offset: 1000, maxExtent: 1000, pageCount: 5), 4);
    expect(pageIndexFromScroll(offset: 500, maxExtent: 1000, pageCount: 5), 2);
    expect(pageIndexFromScroll(offset: 50, maxExtent: 0, pageCount: 5), 0);
    expect(
      pageIndexFromScroll(offset: double.nan, maxExtent: 10, pageCount: 3),
      0,
    );

    for (var page = 0; page < 8; page++) {
      final offset = scrollOffsetForPage(
        pageIndex: page,
        maxExtent: 1400,
        pageCount: 8,
      );
      expect(
        pageIndexFromScroll(offset: offset, maxExtent: 1400, pageCount: 8),
        page,
      );
    }
    expect(scrollOffsetForPage(pageIndex: 3, maxExtent: 0, pageCount: 4), 0);
    expect(scrollOffsetForPage(pageIndex: 0, maxExtent: 100, pageCount: 1), 0);
  });
}
