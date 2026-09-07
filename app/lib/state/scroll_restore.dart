/// 阅读器滚动位置恢复的纯逻辑（可单测，不涉 UI/网络）。
library;

/// 保存像素位置及当时的全宽图片布局；旧记录可以没有宽度。
typedef SavedScrollPosition = ({
  double offset,
  int at,
  double? width,
  double topInset,
});

/// 全宽漫画图片随屏宽等比缩放，顶部系统留白单独换算。
double resizeScrollOffset({
  required double offset,
  required double fromWidth,
  required double toWidth,
  double fromTopInset = 0,
  double toTopInset = 0,
}) {
  if (!offset.isFinite || offset <= 0) return 0;
  if (!fromWidth.isFinite ||
      !toWidth.isFinite ||
      fromWidth <= 0 ||
      toWidth <= 0) {
    return offset;
  }
  if (fromTopInset > 0 && offset <= fromTopInset) {
    return offset / fromTopInset * toTopInset;
  }
  return (offset - fromTopInset) * toWidth / fromWidth + toTopInset;
}

/// 计算应恢复到的滚动偏移：
/// - 未保存（null）或非正值 → 0（回到顶部）；
/// - 超出当前可滚动范围 → clamp 到 maxExtent（图片渐进加载时范围会小）。
double resolveRestoredScroll({
  required double? saved,
  required double maxExtent,
}) {
  if (saved == null || saved <= 0) return 0;
  if (maxExtent <= 0) return 0;
  return saved.clamp(0, maxExtent).toDouble();
}
