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
  );
  late final Animation<double> _opacity = _controller
      .drive(CurveTween(curve: Curves.easeInOut))
      .drive(Tween<double>(begin: 0.45, end: 0.9));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: _opacity,
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

/// 探索列表骨架：封面、标题与元信息的位置对齐 BookTile，加载后不跳布局。
class BookListSkeleton extends StatelessWidget {
  const BookListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '正在加载漫画',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          itemCount: 6,
          itemBuilder: (context, index) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: scheme.surfaceContainerLow,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 64, height: 96, radius: 10),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 12),
                        SkeletonBox(height: 20, radius: 6),
                        SizedBox(height: 12),
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: SkeletonBox(height: 12, radius: 4),
                        ),
                        SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          child: SkeletonBox(height: 12, radius: 4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 书籍详情加载骨架：封面英雄卡 + 标题/作者/标签条 + 紧凑章节行。
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key, this.chapterRows = 6});

  final int chapterRows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Card(
          color: scheme.surfaceContainerLow,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 164, radius: 10),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 22, radius: 6),
                          SizedBox(height: 10),
                          SkeletonBox(width: 90, height: 12, radius: 6),
                          SizedBox(height: 12),
                          SkeletonBox(width: 96, height: 22, radius: 8),
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
                SizedBox(height: 14),
                SkeletonBox(height: 40, radius: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 16, width: 90, radius: 6),
        const SizedBox(height: 12),
        ...List.generate(
          chapterRows,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SkeletonBox(width: 22, height: 12, radius: 4),
                const SizedBox(width: 12),
                const Expanded(child: SkeletonBox(height: 13, radius: 6)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
