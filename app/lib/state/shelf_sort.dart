import 'package:engine/engine.dart';

/// 书架排序：作用于分组、连载状态和本地搜索之后的可见列表。
enum ShelfSort {
  recentlyRead,
  updateTime,
  title,
  author;

  String get id => name;

  String get label => switch (this) {
    recentlyRead => '最近阅读',
    updateTime => '更新时间',
    title => '书名',
    author => '作者',
  };

  static ShelfSort parse(Object? raw) {
    final id = raw is String ? raw.trim() : '';
    return values.where((sort) => sort.id == id).firstOrNull ?? recentlyRead;
  }
}

bool matchesShelfSearch(Book book, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return book.name.toLowerCase().contains(needle) ||
      book.author.toLowerCase().contains(needle);
}

/// [filter]：0=全部 1=连载中 2=已完结（kind 空只出现在「全部」）。
bool matchesShelfKind(Book book, int filter) => switch (filter) {
  2 => book.kind.contains('完结'),
  1 => book.kind.isNotEmpty && !book.kind.contains('完结'),
  _ => true,
};

int compareShelfText(String a, String b) {
  final left = a.trim();
  final right = b.trim();
  if (left.isEmpty != right.isEmpty) return left.isEmpty ? 1 : -1;
  final byValue = left.toLowerCase().compareTo(right.toLowerCase());
  return byValue == 0 ? left.compareTo(right) : byValue;
}

/// 把源站给出的更新时间尽量解析成毫秒时间戳；无法识别则返回 0。
int parseComicUpdateTime(String raw, {DateTime? now}) {
  final text = raw.trim();
  if (text.isEmpty) return 0;
  final clock = now ?? DateTime.now();

  if (RegExp(r'^\d{10,13}$').hasMatch(text)) {
    final value = int.parse(text);
    return text.length >= 13 ? value : value * 1000;
  }

  final named = switch (text) {
    '刚刚' || '剛才' || '刚才' => clock,
    '今天' || '今日' => DateTime(clock.year, clock.month, clock.day),
    '昨天' || '昨日' => DateTime(
      clock.year,
      clock.month,
      clock.day,
    ).subtract(const Duration(days: 1)),
    '前天' => DateTime(
      clock.year,
      clock.month,
      clock.day,
    ).subtract(const Duration(days: 2)),
    _ => null,
  };
  if (named != null) return named.millisecondsSinceEpoch;

  final relative = RegExp(
    r'^(\d+)\s*(秒|分钟|分鐘|小时|小時|天|周|週|月)前$',
  ).firstMatch(text);
  if (relative != null) {
    final amount = int.parse(relative.group(1)!);
    final delta = switch (relative.group(2)!) {
      '秒' => Duration(seconds: amount),
      '分钟' || '分鐘' => Duration(minutes: amount),
      '小时' || '小時' => Duration(hours: amount),
      '天' => Duration(days: amount),
      '周' || '週' => Duration(days: amount * 7),
      _ => Duration(days: amount * 30),
    };
    return clock.subtract(delta).millisecondsSinceEpoch;
  }

  final parsed = _tryParseAbsoluteDate(text, clock);
  return parsed?.millisecondsSinceEpoch ?? 0;
}

DateTime? _tryParseAbsoluteDate(String text, DateTime clock) {
  final normalized = text
      .replaceAll('/', '-')
      .replaceAll('.', '-')
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final ymd = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2})(?::(\d{1,2})(?::(\d{1,2}))?)?)?$',
  ).firstMatch(normalized);
  if (ymd != null) {
    return _dateFromParts(
      int.parse(ymd.group(1)!),
      int.parse(ymd.group(2)!),
      int.parse(ymd.group(3)!),
      hour: int.tryParse(ymd.group(4) ?? '') ?? 0,
      minute: int.tryParse(ymd.group(5) ?? '') ?? 0,
      second: int.tryParse(ymd.group(6) ?? '') ?? 0,
    );
  }
  final md = RegExp(
    r'^(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2})(?::(\d{1,2})(?::(\d{1,2}))?)?)?$',
  ).firstMatch(normalized);
  if (md == null) return DateTime.tryParse(normalized.replaceFirst(' ', 'T'));
  var year = clock.year;
  var date = _dateFromParts(
    year,
    int.parse(md.group(1)!),
    int.parse(md.group(2)!),
    hour: int.tryParse(md.group(3) ?? '') ?? 0,
    minute: int.tryParse(md.group(4) ?? '') ?? 0,
    second: int.tryParse(md.group(5) ?? '') ?? 0,
  );
  if (date == null) return null;
  if (date.isAfter(clock.add(const Duration(days: 1)))) {
    date = _dateFromParts(
      year - 1,
      date.month,
      date.day,
      hour: date.hour,
      minute: date.minute,
      second: date.second,
    );
  }
  return date;
}

DateTime? _dateFromParts(
  int year,
  int month,
  int day, {
  int hour = 0,
  int minute = 0,
  int second = 0,
}) {
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final date = DateTime(year, month, day, hour, minute, second);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

int shelfUpdateMillis(
  Book book, {
  int catalogAt = 0,
  DateTime? now,
}) {
  final parsed = parseComicUpdateTime(book.updateTime, now: now);
  return parsed > 0 ? parsed : catalogAt;
}

List<Book> visibleShelfBooks(
  Iterable<Book> shelf, {
  required bool Function(Book book) matchesGroup,
  String query = '',
  int kindFilter = 0,
  ShelfSort sort = ShelfSort.recentlyRead,
  int Function(Book book)? readAt,
  int Function(Book book)? catalogAt,
  DateTime? now,
}) {
  final books = shelf.where((book) {
    if (!matchesGroup(book)) return false;
    if (!matchesShelfSearch(book, query)) return false;
    return matchesShelfKind(book, kindFilter);
  }).toList();
  books.sort((a, b) {
    final bySort = switch (sort) {
      ShelfSort.recentlyRead =>
        (readAt?.call(b) ?? 0).compareTo(readAt?.call(a) ?? 0),
      ShelfSort.updateTime => shelfUpdateMillis(
        b,
        catalogAt: catalogAt?.call(b) ?? 0,
        now: now,
      ).compareTo(
        shelfUpdateMillis(a, catalogAt: catalogAt?.call(a) ?? 0, now: now),
      ),
      ShelfSort.title => compareShelfText(a.name, b.name),
      ShelfSort.author => compareShelfText(a.author, b.author),
    };
    if (bySort != 0) return bySort;
    final byTitle = compareShelfText(a.name, b.name);
    if (byTitle != 0) return byTitle;
    return a.bookUrl.compareTo(b.bookUrl);
  });
  return books;
}
