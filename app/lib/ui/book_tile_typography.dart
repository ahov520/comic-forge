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
}
