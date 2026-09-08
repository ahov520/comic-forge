import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/reading_history.dart';
import 'resume_reading.dart';
import 'widgets.dart';

class ReadingHistoryScreen extends StatefulWidget {
  const ReadingHistoryScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _opening;
  int _generation = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      if (_query != query) {
        // 用户开始找另一条记录后，旧的续读请求不能抢走当前页面。
        _generation++;
        _opening = null;
      }
      _query = query;
    });
  }

  String _bookName(ReadingHistoryEntry entry) => readingHistoryBookName(entry);

  String _chapterName(ReadingHistoryEntry entry) =>
      readingHistoryChapterName(entry);

  String _sourceName(ReadingHistoryEntry entry) {
    final source = widget.state.sources
        .where((source) => source.id == entry.book.sourceId)
        .firstOrNull;
    return source == null
        ? '来源已移除'
        : (source.name.trim().isEmpty ? '未命名来源' : source.name);
  }

  Widget _withSearch(Widget child) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: '搜索阅读历史',
            hintText: '漫画名、章节或来源',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _search('');
                    },
                  ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _search,
        ),
      ),
      Expanded(child: child),
    ],
  );

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

  Future<void> _remove(ReadingHistoryEntry entry) async {
    if (_opening == entry.key) {
      _generation++;
      setState(() => _opening = null);
    }
    await widget.state.removeReadingHistory(entry.key);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final groups = <String, List<ReadingHistoryEntry>>{};
      for (final entry in widget.state.readingHistory) {
        if (_query.isNotEmpty &&
            ![
              _bookName(entry),
              _chapterName(entry),
              _sourceName(entry),
            ].any((value) => value.toLowerCase().contains(_query))) {
          continue;
        }
        groups.putIfAbsent(readingHistoryDay(entry.at), () => []).add(entry);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('阅读历史')),
        body: _withSearch(
          groups.isEmpty
              ? EmptyStateView(
                  icon: Icons.history,
                  title: widget.state.readingHistory.isEmpty
                      ? '还没有阅读记录'
                      : '没有匹配的阅读记录',
                  message: widget.state.readingHistory.isEmpty
                      ? '阅读过的漫画会按时间显示在这里。'
                      : '试试其他漫画名、章节或来源，或清空搜索。',
                )
              : CustomScrollView(
                  key: ValueKey(_query),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    for (final group in groups.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Semantics(
                            header: true,
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: group.value.length,
                        itemBuilder: (context, index) {
                          final entry = group.value[index];
                          final name = _bookName(entry);
                          final sourceName = _sourceName(entry);
                          final chapter = _chapterName(entry);
                          final opening = _opening == entry.key;
                          return ListTile(
                            key: ValueKey(entry.key),
                            isThreeLine: true,
                            leading: SizedBox(
                              width: 48,
                              height: 64,
                              child: BookCover(url: entry.book.coverUrl),
                            ),
                            title: Tooltip(
                              message: name,
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  chapter,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${readingHistoryTime(entry.at)} · $sourceName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '续读 $name',
                                  onPressed: opening
                                      ? null
                                      : () => _resume(entry),
                                  icon: opening
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.play_arrow_rounded),
                                ),
                                IconButton(
                                  tooltip: '移除 $name 的阅读记录',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _remove(entry),
                                ),
                              ],
                            ),
                            onTap: opening ? null : () => _resume(entry),
                          );
                        },
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
        ),
      );
    },
  );
}
