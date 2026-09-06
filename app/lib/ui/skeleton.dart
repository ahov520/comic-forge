import 'package:flutter/material.dart';

/// 骨架占位块：圆角灰底 + 呼吸脉冲（对齐皮皮喵秒开观感）。
/// 用法：固定尺寸的 [SkeletonBox]，或外面包 Expanded/SizedBox 撑开。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 书籍详情加载骨架：封面块 + 标题/作者/标签条 + 章节行，结构对齐真实布局。
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key, this.chapterRows = 6});

  final int chapterRows;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 110, height: 150, radius: 10),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(height: 20, radius: 6),
                  SizedBox(height: 10),
                  SkeletonBox(width: 90, height: 12, radius: 6),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      SkeletonBox(width: 48, height: 22, radius: 999),
                      SizedBox(width: 6),
                      SkeletonBox(width: 60, height: 22, radius: 999),
                      SizedBox(width: 6),
                      SkeletonBox(width: 40, height: 22, radius: 999),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 14, radius: 6),
        const SizedBox(height: 24),
        SkeletonBox(height: 16, width: 90, radius: 6),
        const SizedBox(height: 12),
        ...List.generate(
          chapterRows,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SkeletonBox(width: 22, height: 12, radius: 4),
                const SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 13, radius: 6)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
