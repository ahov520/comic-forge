/// 阅读器滚动位置恢复的纯逻辑（可单测，不涉 UI/网络）。
library;

/// 计算应恢复到的滚动偏移：
/// - 未保存（null）或非正值 → 0（回到顶部）；
/// - 超出当前可滚动范围 → clamp 到 maxExtent（图片渐进加载时范围会小）。
double resolveRestoredScroll({required double? saved, required double maxExtent}) {
  if (saved == null || saved <= 0) return 0;
  if (maxExtent <= 0) return 0;
  return saved.clamp(0, maxExtent).toDouble();
}
