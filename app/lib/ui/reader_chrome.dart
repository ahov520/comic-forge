import 'dart:ui';

import 'package:flutter/material.dart';

/// 阅读器工具栏渐变遮罩：顶/底黑→透明渐变，保证白字工具栏在浅色漫画上可读。
/// [visible] 为 false 时整体收起（不渲染、不拦截）。
/// 独立组件便于单测（渐变容器随可见性出现/消失）。
class ReaderChromeOverlay extends StatelessWidget {
  const ReaderChromeOverlay({
    super.key,
    required this.visible,
    required this.topInset,
    required this.bottomInset,
    this.topHeight = 72,
    this.bottomHeight = 84,
  });

  final bool visible;
  final double topInset;
  final double bottomInset;
  final double topHeight;
  final double bottomHeight;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    // IgnorePointer：点击穿透到下层翻页点区
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: topInset + topHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: bottomInset + bottomHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 毛玻璃条：对齐 six-screens ④ `backdrop-filter: blur(10px)`。
class ReaderFrostedBar extends StatelessWidget {
  const ReaderFrostedBar({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x8C2A2B33),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

Duration _chromeAnim(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 200);

/// 顶栏：关闭 · 源/书名/章节 · 更多。隐藏时不拦截点击。
class ReaderTopChrome extends StatelessWidget {
  const ReaderTopChrome({
    super.key,
    required this.visible,
    required this.title,
    this.onClose,
    this.onMore,
  });

  final bool visible;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _chromeAnim(context),
      child: IgnorePointer(
        ignoring: !visible,
        child: ReaderFrostedBar(
          child: Row(
            children: [
              IconButton(
                tooltip: '关闭',
                color: Colors.white,
                visualDensity: VisualDensity.compact,
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '阅读设置',
                color: Colors.white,
                visualDensity: VisualDensity.compact,
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏：上一话 · 进度 · 亮度 · 下一话。隐藏时不拦截点击。
class ReaderBottomChrome extends StatelessWidget {
  const ReaderBottomChrome({
    super.key,
    required this.visible,
    required this.progressLabel,
    required this.canPrev,
    required this.canNext,
    this.onPrev,
    this.onNext,
    this.onBrightness,
    this.onCatalog,
  });

  final bool visible;
  final String progressLabel;
  final bool canPrev;
  final bool canNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onBrightness;
  final VoidCallback? onCatalog;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _chromeAnim(context),
      child: IgnorePointer(
        ignoring: !visible,
        child: ReaderFrostedBar(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.chevron_left,
                label: '上一话',
                enabled: canPrev,
                onTap: onPrev,
              ),
              _NavItem(
                icon: Icons.menu,
                label: progressLabel,
                enabled: onCatalog != null,
                onTap: onCatalog,
              ),
              _NavItem(
                icon: Icons.wb_sunny_outlined,
                label: '亮度',
                onTap: onBrightness,
              ),
              _NavItem(
                icon: Icons.chevron_right,
                label: '下一话',
                enabled: canNext,
                onTap: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : Colors.white38;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
