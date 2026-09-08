import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/reading_history.dart';
import 'book_tile_typography.dart';
import 'reading_history_screen.dart';
import 'resume_reading.dart';
import 'widgets.dart';

bool continueReadingStripVisible(AppState state) =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    state.readingHistory.isNotEmpty;

/// Android 书架顶部的最近阅读条：封面 + 章节/进度，点按走现有续读。
class ContinueReadingStrip extends StatefulWidget {
  const ContinueReadingStrip({super.key, required this.state});

  final AppState state;

  static const Key stripKey = Key('continue-reading-strip');

  @override
  State<ContinueReadingStrip> createState() => _ContinueReadingStripState();
}

class _ContinueReadingStripState extends State<ContinueReadingStrip> {
  String? _opening;
  int _generation = 0;

  bool _current(int generation, ReadingHistoryEntry entry) =>
      mounted &&
      generation == _generation &&
      ModalRoute.of(context)?.isCurrent != false &&
      widget.state.readingHistory.any((item) => item.key == entry.key);

  void _openDetail(ReadingHistoryEntry entry) {
    openReadingHistoryDetail(context, widget.state, entry);
  }

  Future<void> _resume(ReadingHistoryEntry entry) async {
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() => _opening = entry.key);
    try {
      await resumeReadingHistory(
        context: context,
        state: widget.state,
        entry: entry,
        isCurrent: () => _current(generation, entry),
        openDetail: () {
          if (mounted) _openDetail(entry);
        },
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _opening = null);
    }
  }

  void _openHistory() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadingHistoryScreen(state: widget.state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = continueReadingEntries(widget.state.readingHistory);
    if (entries.isEmpty) return const SizedBox.shrink();
    final titleStyle = BookTileTypography.shelfTitle(context);
    final hintStyle = BookTileTypography.metadata(context);
    final titleHeight = BookTileTypography.lineHeight(context, titleStyle);
    final hintHeight = BookTileTypography.lineHeight(context, hintStyle);
    return KeyedSubtree(
      key: ContinueReadingStrip.stripKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '继续阅读',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                Tooltip(
                  message: '查看全部阅读历史',
                  child: TextButton(
                    onPressed: _openHistory,
                    child: const Text('全部'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96 + 6 + titleHeight + hintHeight + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final name = readingHistoryBookName(entry);
                final hint = continueReadingHint(entry);
                final opening = _opening == entry.key;
                return Tooltip(
                  message: '续读 $name',
                  child: SizedBox(
                    width: 96,
                    child: InkWell(
                      key: ValueKey('continue-reading-${entry.key}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: opening ? null : () => _resume(entry),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 72,
                            height: 96,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: BookCover(
                                    url: entry.book.coverUrl,
                                    width: 72,
                                    height: 96,
                                  ),
                                ),
                                if (opening)
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Color(0x66000000),
                                      child: Center(
                                        child: SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          Text(
                            hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hintStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
