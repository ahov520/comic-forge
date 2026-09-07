import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/download_queue.dart';
import 'downloads_screen.dart';

class DownloadSelectionSheet extends StatefulWidget {
  const DownloadSelectionSheet({
    super.key,
    required this.state,
    required this.book,
    required this.chapters,
  });

  final AppState state;
  final Book book;
  final List<Chapter> chapters;

  @override
  State<DownloadSelectionSheet> createState() => _DownloadSelectionSheetState();
}

class _DownloadSelectionSheetState extends State<DownloadSelectionSheet> {
  final Set<int> _selected = {};
  bool _busy = false;
  String? _error;

  Set<int> get _eligible => {
    for (var i = 0; i < widget.chapters.length; i++)
      if (_canSelect(i)) i,
  };

  bool _canSelect(int index) {
    if (widget.chapters[index].url.isEmpty) return false;
    final task = widget.state.downloads.taskFor(
      widget.book,
      widget.chapters[index],
    );
    return task == null || task.status == DownloadStatus.failed;
  }

  Set<int> get _unread {
    final progress = widget.state.progressFor(widget.book.bookUrl);
    final index = progress?.sourceId == (widget.book.sourceId ?? '')
        ? widget.chapters.indexWhere(
            (chapter) => chapter.url == progress?.chapterUrl,
          )
        : -1;
    return _eligible.where((i) => i > index).toSet();
  }

  @override
  void initState() {
    super.initState();
    _selected.addAll(_unread);
  }

  Future<void> _submit(Set<int> selected) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final added = await widget.state.downloads.enqueue(
        widget.book,
        widget.chapters,
        selected,
      );
      if (mounted) Navigator.of(context).pop(added);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '无法加入下载队列，请检查可用空间后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state.downloads,
    builder: (context, _) {
      final eligible = _eligible;
      final selected = _selected.intersection(eligible);
      final allSelected =
          eligible.isNotEmpty && selected.length == eligible.length;
      return SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '离线下载 · ${widget.book.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selected.clear();
                            if (!allSelected) _selected.addAll(eligible);
                          }),
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selected
                              ..clear()
                              ..addAll(_unread);
                          }),
                    child: const Text('选中未读'),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.chapters.length,
                  itemBuilder: (context, i) {
                    final chapter = widget.chapters[i];
                    final task = widget.state.downloads.taskFor(
                      widget.book,
                      chapter,
                    );
                    return CheckboxListTile(
                      key: ValueKey(chapter.url),
                      title: Text(
                        chapter.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: task == null
                          ? null
                          : Text(downloadStatusLabel(task)),
                      value: selected.contains(i),
                      onChanged: _busy || !eligible.contains(i)
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _selected.add(i);
                              } else {
                                _selected.remove(i);
                              }
                            }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    if (_error != null) Text(_error!),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy || selected.isEmpty
                            ? null
                            : () => _submit(_selected.intersection(_eligible)),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          _busy ? '正在加入…' : '加入下载队列（${selected.length} 话）',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
