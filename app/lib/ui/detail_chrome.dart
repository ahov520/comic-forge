import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../state/app_state.dart';
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
    this.onRead,
  });

  static const coverWidth = 120.0;
  static const coverHeight = 164.0;

  final Book book;
  final String? sourceName;
  final int? switchCount;
  final VoidCallback? onSwitchSource;
  final String? readLabel;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tags = splitKindTags(book.kind);
    final source = sourceName?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(
                  url: book.coverUrl,
                  width: coverWidth,
                  height: coverHeight,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
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
                                  (k) => Chip(
                                    label: Text(k),
                                    labelStyle: const TextStyle(fontSize: 11),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: EdgeInsets.zero,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (book.introduce.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                book.introduce,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            if (onRead != null && readLabel != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRead,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(readLabel!),
              ),
            ],
          ],
        ),
      ),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fg = isCurrent ? scheme.onPrimaryContainer : scheme.onSurface;
    final numColor = isCurrent ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 28, maxWidth: 44),
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
                if (isCurrent)
                  Icon(Icons.bookmark, size: 16, color: scheme.primary),
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
  });

  final String bookName;
  final AsyncSnapshot<List<(ComicSource, Book)>> snapshot;
  final AppState state;
  final void Function(ComicSource source, Book book) onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text('换源 · $bookName', style: textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (!snapshot.hasData) {
      return const BookListSkeleton();
    }
    final hits = snapshot.data!;
    if (hits.isEmpty) {
      return const EmptyStateView(
        icon: Icons.swap_horiz,
        title: '其它源没有搜到同名书',
        message: '可以稍后重试，或到「源」页启用更多漫画源。',
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
