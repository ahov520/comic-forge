import 'package:flutter/material.dart';

/// 书卡与加载占位共用字号和行高，使骨架随系统字号缩放。
abstract final class BookTileTypography {
  static TextStyle title(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600);

  static TextStyle metadata(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
}
