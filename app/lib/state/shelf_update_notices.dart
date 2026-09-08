import 'dart:convert';

import 'package:engine/engine.dart';

import 'shelf_updates.dart';

/// 点按通知后打开的书架漫画。
class ShelfUpdateOpenRequest {
  const ShelfUpdateOpenRequest({required this.bookUrl, required this.sourceId});

  final String bookUrl;
  final String sourceId;

  Map<String, dynamic> toMap() => {'bookUrl': bookUrl, 'sourceId': sourceId};

  static ShelfUpdateOpenRequest? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final bookUrl = raw['bookUrl'];
    final sourceId = raw['sourceId'];
    if (bookUrl is! String || bookUrl.isEmpty) return null;
    return ShelfUpdateOpenRequest(
      bookUrl: bookUrl,
      sourceId: sourceId is String ? sourceId : '',
    );
  }
}

class ShelfUpdateNotice {
  const ShelfUpdateNotice({required this.book, required this.badge});

  final Book book;
  final ShelfUpdateBadge badge;

  String get key => shelfUpdateNoticeKey(book);
}

String shelfUpdateNoticeKey(Book book) =>
    jsonEncode([book.sourceId ?? '', book.bookUrl]);

int shelfUpdateNoticeId(String key) => key.hashCode & 0x7fffffff;

String shelfUpdateNoticeBody(ShelfUpdateBadge badge) {
  final title = badge.latestTitle.trim();
  final unread = badge.unreadCount;
  if (unread != null && unread > 0) {
    return title.isEmpty ? '未读 $unread 话' : '未读 $unread 话 · $title';
  }
  return title.isEmpty ? '有新章节' : '更新至 $title';
}

/// 只在已有目录或角标的漫画上，把「新出现/变化的角标」转成通知。
List<ShelfUpdateNotice> shelfUpdatesToNotify({
  required Iterable<Book> shelf,
  required Map<String, String> previousTokens,
  required Set<String> previouslyCataloged,
  required Map<String, String> notifiedTokens,
  required ShelfUpdateBadge? Function(Book book) badgeFor,
}) {
  final notices = <ShelfUpdateNotice>[];
  for (final book in shelf) {
    final badge = badgeFor(book);
    if (badge == null) continue;
    final key = shelfUpdateNoticeKey(book);
    if (notifiedTokens[key] == badge.token) continue;
    if (previousTokens[key] == badge.token) continue;
    final knownBefore =
        previouslyCataloged.contains(key) || previousTokens.containsKey(key);
    if (!knownBefore) continue;
    notices.add(ShelfUpdateNotice(book: book, badge: badge));
  }
  return notices;
}
