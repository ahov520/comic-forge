/// 章内页进度的纯逻辑（可单测，不涉 UI/网络）。
library;

/// 1-based 页码文案，例如 `3/20`。无页时为空串。
String pageProgressLabel(int index, int count) {
  if (count <= 0) return '';
  final page = index.clamp(0, count - 1) + 1;
  return '$page/$count';
}

/// 滚动位置对应的 0-based 页码；等分页高近似，页数不足 2 时为 0。
int pageIndexFromScroll({
  required double offset,
  required double maxExtent,
  required int pageCount,
}) {
  if (pageCount <= 1 || !offset.isFinite || !maxExtent.isFinite) return 0;
  if (maxExtent <= 0) return 0;
  final ratio = (offset / maxExtent).clamp(0.0, 1.0);
  return (ratio * (pageCount - 1)).round();
}

/// 跳到指定 0-based 页时的滚动偏移，与 [pageIndexFromScroll] 互逆。
double scrollOffsetForPage({
  required int pageIndex,
  required double maxExtent,
  required int pageCount,
}) {
  if (pageCount <= 1 || !maxExtent.isFinite || maxExtent <= 0) return 0;
  final page = pageIndex.clamp(0, pageCount - 1);
  return page / (pageCount - 1) * maxExtent;
}

/// 0–1 章内进度；无页为 0，仅一页为 1。
double pageProgressFraction(int index, int count) {
  if (count <= 0) return 0;
  if (count == 1) return 1;
  return index.clamp(0, count - 1) / (count - 1);
}
