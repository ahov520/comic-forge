import 'package:flutter/material.dart';

import 'book_tile_typography.dart';
import 'detail_cover_layout.dart';

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

/// 书籍列表骨架：对齐探索、搜索和换源面板的 BookTile。
class BookListSkeleton extends StatelessWidget {
  const BookListSkeleton({super.key, this.showShelfAction = true});

  final bool showShelfAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleHeight = BookTileTypography.lineHeight(
      context,
      BookTileTypography.title(context),
    );
    final metadataHeight = BookTileTypography.lineHeight(
      context,
      BookTileTypography.metadata(context),
    );
    return Semantics(
      label: '正在加载漫画',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: 6,
          itemBuilder: (context, index) => Card(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            color: scheme.brightness == Brightness.light
                ? scheme.surfaceContainerLowest
                : scheme.surfaceContainerLow,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SkeletonBox(width: 60, height: 80, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: titleHeight, radius: 6),
                        const SizedBox(height: 4),
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: SkeletonBox(height: metadataHeight, radius: 4),
                        ),
                        const SizedBox(height: 2),
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          child: SkeletonBox(height: metadataHeight, radius: 4),
                        ),
                      ],
                    ),
                  ),
                  if (showShelfAction)
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: SkeletonBox(width: 20, height: 20, radius: 10),
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
    return Semantics(
      label: '正在加载漫画详情',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: scheme.brightness == Brightness.light
                  ? scheme.surfaceContainerLowest
                  : scheme.surfaceContainerLow,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailCoverLayout(
                      cover: SkeletonBox(
                        width: DetailCoverLayout.coverWidth,
                        height: DetailCoverLayout.coverHeight,
                        radius: 10,
                      ),
                      metadata: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 22, radius: 6),
                          SizedBox(height: 10),
                          SkeletonBox(width: 90, height: 12, radius: 6),
                          SizedBox(height: 12),
                          SkeletonBox(width: 96, height: 22, radius: 8),
                          SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              SkeletonBox(width: 48, height: 22, radius: 999),
                              SkeletonBox(width: 60, height: 22, radius: 999),
                              SkeletonBox(width: 40, height: 22, radius: 999),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: SkeletonBox(height: 44, radius: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(height: 24, width: 90, radius: 6),
            ),
            const SizedBox(height: 6),
            ...List.generate(
              chapterRows,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 28, height: 12, radius: 4),
                    const SizedBox(width: 12),
                    const Expanded(child: SkeletonBox(height: 20, radius: 6)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
