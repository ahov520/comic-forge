import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';
import 'book_detail_screen.dart';
import 'book_tile_typography.dart';
import 'reader_screen.dart';
import 'skeleton.dart';

/// 顶层页面统一的标题字号与无障碍层级。
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// 书架与探索共用的单选筛选标签，对齐 six-screens `.chip`（7×14、13px）。
class FilterChoiceChip extends StatelessWidget {
  const FilterChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: label,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(vertical: 7),
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      backgroundColor: scheme.brightness == Brightness.light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      selectedColor: scheme.primary,
      side: BorderSide(
        color: selected
            ? scheme.primary
            : scheme.outlineVariant.withValues(alpha: 0.6),
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 13,
        height: 1.0,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 书架状态筛选条，对齐 six-screens ① `.chip-row`（间距 8、底边距 12）。
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({super.key, required this.children});

  final List<Widget> children;

  static const padding = EdgeInsets.fromLTRB(20, 0, 20, 12);
  static const double spacing = 8;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(spacing: spacing, runSpacing: spacing, children: children),
    );
  }
}

/// 阅读器前的统一封面组件。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.url,
    this.width = 96,
    this.height = 128,
  });

  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: url.isEmpty
            ? Icon(Icons.menu_book_outlined, color: scheme.outline)
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: width,
                height: height,
                // 加载中用呼吸骨架，替代死灰块
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : SkeletonBox(width: width, height: height),
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
      ),
    );
  }
}

/// 来源角标：搜索/探索卡片与详情换源入口共用。
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.label, this.onTap, this.count});

  final String label;
  final VoidCallback? onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final switchable = onTap != null;
    Widget chip = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public,
                  size: 14,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (switchable) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: scheme.onSecondaryContainer,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if ((count ?? 0) > 0) {
      chip = Badge.count(
        count: count!,
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        child: chip,
      );
    }
    return Tooltip(
      message: switchable ? '换源：$label' : '来源：$label',
      child: chip,
    );
  }
}

/// 搜索/探索结果条目。
class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.state,
    this.sourceLabel,
    this.onTap,
    this.showShelfAction = true,
  });

  final Book book;
  final AppState state;

  /// 来源标签（聚合搜索结果显示用；null 不显示）。
  final String? sourceLabel;

  /// 覆盖默认「打开详情」；换源面板点选用。
  final VoidCallback? onTap;

  /// 换源等场景隐藏收藏，避免误触。
  final bool showShelfAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = [
      if (book.author.trim().isNotEmpty) book.author.trim(),
      if (book.kind.trim().isNotEmpty) book.kind.trim(),
    ].join(' · ');
    final source = sourceLabel?.trim() ?? '';
    final chapter = book.lastChapter.trim();
    final chapterLabel = chapter.startsWith('更新') || chapter.startsWith('最新')
        ? chapter
        : '更新至 $chapter';
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      color: scheme.brightness == Brightness.light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            onTap ??
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookDetailScreen(book: book, appState: state),
              ),
            ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCover(url: book.coverUrl, width: 60, height: 80),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BookTileTypography.title(context),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: metadata,
                        child: Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BookTileTypography.metadata(context),
                        ),
                      ),
                    ],
                    if (chapter.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        chapterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BookTileTypography.metadata(context),
                      ),
                    ],
                    if (source.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Tooltip(
                        message: '来源：$source',
                        child: Text(
                          '源: $source',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BookTileTypography.metadata(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showShelfAction) ShelfButton(book: book, state: state),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表与详情共用的收藏操作，外部书架变更也会即时同步。
class ShelfButton extends StatelessWidget {
  const ShelfButton({
    super.key,
    required this.book,
    required this.state,
    this.iconSize = 20,
  });

  final Book book;
  final AppState state;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final saved = state.inShelf(book);
        return IconButton(
          tooltip: saved ? '移出书架' : '加入书架',
          isSelected: saved,
          iconSize: iconSize,
          onPressed: () => state.toggleShelf(book),
          icon: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: Icon(
              saved ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(saved),
              color: scheme.primary,
            ),
          ),
        );
      },
    );
  }
}

/// 带下一步指引的空状态；窄屏、键盘展开或大字号时仍可滚动。
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 44),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.primary,
                    textStyle: textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!, textAlign: TextAlign.center),
                ),
              ],
              if (secondaryActionLabel != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(
                    secondaryActionLabel!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误与空状态共用布局；恢复来源等操作优先，重试作为次要操作。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.error,
    this.title = '暂时无法加载内容',
    this.message,
    this.onRetry,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.cloud_off_outlined,
  });
  final Object? error;
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  /// 附加动作（如「启用该源并重试」）。
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null;
    return EmptyStateView(
      icon: icon,
      title: title,
      message: message ?? (error == null ? '检查网络后重试。' : '加载失败：$error'),
      actionLabel: hasAction ? actionLabel : (onRetry == null ? null : '重试'),
      onAction: hasAction ? onAction : onRetry,
      secondaryActionLabel: hasAction && onRetry != null ? '重试' : null,
      onSecondaryAction: onRetry,
    );
  }
}

/// 阅读器入口：详情页章节 → 图片流（带章节导航与进度记忆）。
void openReader(
  BuildContext context,
  SourceRuntime runtime,
  Book book,
  List<Chapter> chapters,
  int index,
  AppState? appState,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReaderScreen(
        runtime: runtime,
        book: book,
        chapters: chapters,
        initialIndex: index,
        appState: appState,
      ),
    ),
  );
}
