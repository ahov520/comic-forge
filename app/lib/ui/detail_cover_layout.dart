import 'package:flutter/material.dart';

/// 封面与文字共用的自适应布局，让详情加载前后保持相同位置。
class DetailCoverLayout extends StatelessWidget {
  const DetailCoverLayout({
    super.key,
    required this.cover,
    required this.metadata,
  });

  static const coverWidth = 120.0;
  static const coverHeight = 164.0;

  final Widget cover;
  final Widget metadata;

  @override
  Widget build(BuildContext context) {
    final bodySize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
    // 为文字保留约八个汉字的宽度，大字号时转为上下排列。
    final minMetadataWidth =
        MediaQuery.textScalerOf(context).scale(bodySize) * 8;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth - coverWidth - 12 < minMetadataWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: cover),
              const SizedBox(height: 12),
              metadata,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(width: 12),
            Expanded(child: metadata),
          ],
        );
      },
    );
  }
}
