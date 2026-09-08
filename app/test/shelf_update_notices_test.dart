import 'package:comic_forge/state/shelf_update_notices.dart';
import 'package:comic_forge/state/shelf_updates.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Book book(String id) => Book(
    name: '漫画 $id',
    sourceId: 'src',
    bookUrl: 'https://notify.example/$id',
  );

  ShelfUpdateBadge badge(String title, {int? unread = 1}) => ShelfUpdateBadge(
    token: shelfUpdateToken('src', 'https://notify.example/$title', title),
    label: unread == null ? '更新' : '未读 $unread',
    latestTitle: title,
    unreadCount: unread,
  );

  test('首次取得目录不通知；已有目录后新话才通知', () {
    final one = book('one');
    final notices = shelfUpdatesToNotify(
      shelf: [one],
      previousTokens: const {},
      previouslyCataloged: const {},
      notifiedTokens: const {},
      badgeFor: (_) => badge('第3话', unread: 3),
    );
    expect(notices, isEmpty);

    final next = shelfUpdatesToNotify(
      shelf: [one],
      previousTokens: {
        shelfUpdateNoticeKey(one): badge('第3话', unread: 3).token,
      },
      previouslyCataloged: {shelfUpdateNoticeKey(one)},
      notifiedTokens: const {},
      badgeFor: (_) => badge('第5话', unread: 5),
    );
    expect(next, hasLength(1));
    expect(next.single.book.bookUrl, one.bookUrl);
    expect(next.single.badge.latestTitle, '第5话');
  });

  test('追上进度后再更新会通知；同一令牌不重复；未读消失不通知', () {
    final one = book('one');
    final key = shelfUpdateNoticeKey(one);
    final fresh = badge('第6话', unread: 1);
    expect(
      shelfUpdatesToNotify(
        shelf: [one],
        previousTokens: const {},
        previouslyCataloged: {key},
        notifiedTokens: const {},
        badgeFor: (_) => fresh,
      ),
      hasLength(1),
    );
    expect(
      shelfUpdatesToNotify(
        shelf: [one],
        previousTokens: {key: fresh.token},
        previouslyCataloged: {key},
        notifiedTokens: const {},
        badgeFor: (_) => fresh,
      ),
      isEmpty,
    );
    expect(
      shelfUpdatesToNotify(
        shelf: [one],
        previousTokens: {key: badge('第4话').token},
        previouslyCataloged: {key},
        notifiedTokens: {key: fresh.token},
        badgeFor: (_) => fresh,
      ),
      isEmpty,
    );
    expect(
      shelfUpdatesToNotify(
        shelf: [one],
        previousTokens: {key: badge('第4话').token},
        previouslyCataloged: {key},
        notifiedTokens: const {},
        badgeFor: (_) => null,
      ),
      isEmpty,
    );
  });

  test('通知正文包含未读数和最新话', () {
    expect(shelfUpdateNoticeBody(badge('第12话', unread: 3)), '未读 3 话 · 第12话');
    expect(shelfUpdateNoticeBody(badge('第12话', unread: null)), '更新至 第12话');
    expect(
      shelfUpdateNoticeBody(
        const ShelfUpdateBadge(
          token: 't',
          label: '未读',
          latestTitle: '',
          unreadCount: 2,
        ),
      ),
      '未读 2 话',
    );
  });
}
