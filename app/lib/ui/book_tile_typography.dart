import 'package:flutter/material.dart';

/// 书卡、书架与加载占位共用字号和行高，随系统字号缩放。
abstract final class BookTileTypography {
  static TextStyle title(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600);

  static TextStyle metadata(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  static TextStyle shelfTitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodySmall!.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600);

  /// 探索/搜索书卡「加入 / 已在」短标签，与 48px 点击区一起用。
  static TextStyle shelfActionLabel(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall!
      .copyWith(fontSize: 11, height: 1.1, fontWeight: FontWeight.w600);

  static const double shelfActionIconSize = 16;
  static const double shelfActionIconGap = 2;
  static const BoxConstraints shelfActionConstraints = BoxConstraints(
    minWidth: 48,
    minHeight: 48,
  );

  /// 书卡收藏操作的图标+短标签列，骨架与真实按钮共用以免加载完成时跳动。
  static Widget shelfActionColumn({
    required Widget icon,
    required Widget label,
  }) => ConstrainedBox(
    constraints: shelfActionConstraints,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(height: shelfActionIconGap),
          label,
        ],
      ),
    ),
  );

  static double lineHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  static double textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
