import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';
import 'detail_cover_layout.dart';
import 'skeleton.dart';
import 'widgets.dart';

/// 把书籍 kind 拆成最多 5 个标签（中英分隔符）。
List<String> splitKindTags(String kind) => kind
    .split(RegExp(r'[,，|/\s]+'))
    .where((k) => k.isNotEmpty)
    .take(5)
    .toList();

/// 详情封面英雄区：大封面 + 来源换源角标 + 主阅读按钮。
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.book,
    this.sourceName,
    this.switchCount,
    this.onSwitchSource,
    this.readLabel,
    this.readHint,
    this.readIcon = Icons.play_arrow_rounded,
    this.onRead,
  });

  static const coverWidth = DetailCoverLayout.coverWidth;
  static const coverHeight = DetailCoverLayout.coverHeight;

  final Book book;
  final String? sourceName;
  final int? switchCount;
  final VoidCallback? onSwitchSource;
  final String? readLabel;
  final String? readHint;
  final IconData readIcon;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tags = splitKindTags(book.kind);
    final source = sourceName?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      color: scheme.brightness == Brightness.light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailCoverLayout(
              cover: BookCover(
                url: book.coverUrl,
                width: coverWidth,
                height: coverHeight,
              ),
              metadata: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.name,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (source.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SourceBadge(
                          label: source,
                          onTap: onSwitchSource,
                          count: switchCount,
                        ),
                      ),
                    ),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tags
                            .map(
                              (k) => Tooltip(
                                message: k,
                                child: Chip(
                                  label: Text(
                                    k,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  labelStyle: textTheme.labelSmall,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
            if (book.introduce.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailIntroduction(
                key: ValueKey(book.bookUrl),
                text: book.introduce,
              ),
            ],
            if (onRead != null && readLabel != null) ...[
              const SizedBox(height: 12),
              if (readHint != null) ...[
                Text(
                  readHint!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: textTheme.labelLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onRead,
                icon: Icon(readIcon, size: 20),
                label: Text(readLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 简介保持三行预览；只有实际溢出时才提供展开入口。
class _DetailIntroduction extends StatefulWidget {
  const _DetailIntroduction({super.key, required this.text});

  final String text;

  @override
  State<_DetailIntroduction> createState() => _DetailIntroductionState();
}

class _DetailIntroductionState extends State<_DetailIntroduction> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(context).style.merge(
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = preview.didExceedMaxLines;
        preview.dispose();
        return AnimatedSize(
          alignment: Alignment.topCenter,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.text,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                style: style,
              ),
              if (overflows)
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    expanded: _expanded,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      iconAlignment: IconAlignment.end,
                      label: Text(_expanded ? '收起简介' : '展开简介'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 紧凑章节行：当前话用强调底+书签。
class ChapterTile extends StatelessWidget {
  const ChapterTile({
    super.key,
    required this.index,
    required this.title,
    required this.isCurrent,
    required this.onTap,
  });

  final int index;
  final String title;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final numberFontSize = textTheme.labelMedium?.fontSize ?? 12;
    final numberScale =
        MediaQuery.textScalerOf(context).scale(numberFontSize) / numberFontSize;
    final fg = enabled
        ? (isCurrent ? scheme.onPrimaryContainer : scheme.onSurface)
        : scheme.onSurface.withValues(alpha: 0.38);
    final numColor = enabled
        ? (isCurrent ? scheme.primary : scheme.onSurfaceVariant)
        : fg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Material(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 28 * numberScale,
                    maxWidth: 44 * numberScale,
                  ),
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: textTheme.labelMedium?.copyWith(
                      color: numColor,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (isCurrent) Icon(Icons.bookmark, size: 16, color: numColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 换源底部面板：加载骨架 / 空态 / BookTile 列表。
class SwitchSourcePanel extends StatelessWidget {
  const SwitchSourcePanel({
    super.key,
    required this.bookName,
    required this.snapshot,
    required this.state,
    required this.onPick,
    this.onRetry,
  });

  final String bookName;
  final AsyncSnapshot<List<(ComicSource, Book)>> snapshot;
  final AppState state;
  final void Function(ComicSource source, Book book) onPick;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                header: true,
                child: Text(
                  '换源 · $bookName',
                  style: textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (snapshot.hasError) {
      return EmptyStateView(
        icon: Icons.cloud_off_outlined,
        title: '暂时无法查找其它来源',
        message: '检查网络后重试，或到「源」页检查漫画源。',
        actionLabel: onRetry == null ? null : '重试',
        onAction: onRetry,
      );
    }
    if (!snapshot.hasData) {
      return const BookListSkeleton(showShelfAction: false);
    }
    final hits = snapshot.data!;
    if (hits.isEmpty) {
      return EmptyStateView(
        icon: Icons.swap_horiz,
        title: '其它源没有搜到同名书',
        message: '可以稍后重试，或到「源」页启用更多漫画源。',
        actionLabel: onRetry == null ? null : '重新查找',
        onAction: onRetry,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final (source, book) = hits[i];
        final name = source.name.trim().isEmpty ? source.id : source.name;
        return BookTile(
          book: book,
          state: state,
          sourceLabel: name,
          showShelfAction: false,
          onTap: () => onPick(source, book),
        );
      },
    );
  }
}
