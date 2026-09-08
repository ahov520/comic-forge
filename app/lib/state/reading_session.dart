import 'package:engine/engine.dart';

import 'reading_stats.dart';

/// 当前已加载章节的可见阅读时间；暂停、切话和退出时结束当前时间段。
class ReadingSession {
  ReadingSession(this.stats);

  final ReadingStats stats;
  Book? _book;
  Chapter? _chapter;
  DateTime? _startedAt;
  bool _active = false;

  Future<void> openChapter(Book book, Chapter chapter) async {
    final closing = closeChapter();
    _book = Book.fromJson(book.toJson());
    _chapter = Chapter.fromJson(chapter.toJson());
    final opening = _resume();
    await closing;
    await opening;
  }

  Future<void> setActive(bool active) async {
    if (_active == active) return;
    _active = active;
    if (active) {
      await _resume();
    } else {
      final saving = checkpoint();
      _startedAt = null;
      await saving;
    }
  }

  Future<void> _resume() async {
    final book = _book;
    final chapter = _chapter;
    if (!_active || book == null || chapter == null) return;
    final at = stats.now;
    _startedAt = at;
    await stats.record(book, chapter, from: at, to: at);
  }

  Future<void> checkpoint() async {
    final from = _startedAt;
    final book = _book;
    final chapter = _chapter;
    if (from == null || book == null || chapter == null) return;
    final to = stats.now;
    _startedAt = to;
    await stats.record(book, chapter, from: from, to: to);
  }

  Future<void> closeChapter() async {
    final saving = checkpoint();
    _startedAt = null;
    _book = null;
    _chapter = null;
    await saving;
  }
}
