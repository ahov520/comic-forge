import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/chapter_bookmarks.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late ComicSource source;

  Book book(String name, {String? url, String? sourceId}) => Book(
    name: name,
    bookUrl: url ?? 'https://bookmark.example/$name',
    sourceId: sourceId ?? source.id,
  );

  Chapter chapter(Book target, int index) =>
      Chapter(title: '第${index + 1}话', url: '${target.bookUrl}/$index');

  Future<bool> pin(Book target, int index) => state.toggleChapterBookmark(
    target,
    chapter: chapter(target, index),
    chapterIndex: index,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    source = ComicSource.fromJson({
      'id': 'bookmark-source',
      'name': '书签源',
      'url': 'https://bookmark.example',
      'rules': <String, dynamic>{},
    });
    await state.addSourceManual(source);
  });
  tearDown(() => state.dispose());

  test('添加当前话书签，再点一次移除，跨重启保留且不影响进度', () async {
    final a = book('甲漫画')..coverUrl = 'https://bookmark.example/cover.png';
    await state.saveProgress(
      a,
      chapterUrl: chapter(a, 2).url,
      chapterTitle: chapter(a, 2).title,
      chapterIndex: 2,
      chapterCount: 10,
    );
    expect(await pin(a, 2), isTrue);
    expect(state.bookmarksFor(a).single.chapter.title, '第3话');
    expect(state.isChapterBookmarked(a, chapter(a, 2)), isTrue);
    a.name = '被外部修改的对象';
    expect(state.bookmarksFor(a).single.book.name, '甲漫画');

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.bookmarksFor(a).single.book.name, '甲漫画');
    expect(restored.bookmarksFor(a).single.book.coverUrl, a.coverUrl);
    expect(restored.bookmarksFor(a).single.chapter.url, chapter(a, 2).url);
    expect(restored.progressFor(a.bookUrl)?.chapterIndex, 2);
    expect(restored.readingHistory.single.chapterIndex, 2);

    expect(await pin(a, 2), isFalse);
    expect(state.bookmarksFor(a), isEmpty);
    expect(await pin(a, 2), isTrue);
    expect(state.bookmarksFor(a).single.book.name, '被外部修改的对象');
  });

  test('按源和书籍链接隔离，同一漫画多话各自一条且新到旧排序', () async {
    final a = book('同名漫画', url: '/same', sourceId: 'a');
    final b = book('同名漫画', url: '/same', sourceId: 'b');
    final other = book('同名漫画', url: '/other', sourceId: 'a');
    expect(await pin(a, 0), isTrue);
    expect(await pin(a, 4), isTrue);
    expect(await pin(b, 1), isTrue);
    expect(await pin(other, 2), isTrue);
    expect(state.bookmarksFor(a).map((e) => e.chapterIndex), [4, 0]);
    expect(state.bookmarksFor(b).single.chapterIndex, 1);
    expect(state.bookmarksFor(other).single.chapterIndex, 2);
    expect(state.chapterBookmarks.length, 4);
    expect(await pin(a, 0), isFalse);
    expect(state.bookmarksFor(a).single.chapterIndex, 4);
  });

  test('空链接或坏数据不会写入，损坏偏好只丢掉坏记录', () async {
    final a = book('有效漫画');
    expect(
      await state.toggleChapterBookmark(
        a,
        chapter: Chapter(title: '无链接'),
        chapterIndex: 0,
      ),
      isFalse,
    );
    expect(state.chapterBookmarks, isEmpty);
    expect(
      await state.toggleChapterBookmark(
        Book(name: '无链接漫画', sourceId: source.id),
        chapter: chapter(a, 0),
        chapterIndex: 0,
      ),
      isFalse,
    );

    SharedPreferences.setMockInitialValues({
      'cf.sources': jsonEncode([source.toJson()]),
      'cf.chapterBookmarks': jsonEncode([
        'bad',
        {
          'book': a.toJson(),
          'chapter': chapter(a, 1).toJson(),
          'chapterIndex': 1,
          'at': 50,
        },
        {
          'book': {'bookUrl': ''},
          'chapter': {'title': '坏', 'url': '/x'},
          'chapterIndex': 0,
          'at': 90,
        },
        {
          'book': book('另一本').toJson(),
          'chapter': chapter(book('另一本'), 3).toJson(),
          'chapterIndex': 3,
          'at': 80,
        },
      ]),
    });
    await state.load();
    expect(state.chapterBookmarks.map((e) => e.book.name), ['另一本', '有效漫画']);
  });

  test('移除书签不影响进度，并发写入以最后一次内存为准', () async {
    final a = book('甲');
    final b = book('乙');
    await state.saveProgress(
      a,
      chapterUrl: chapter(a, 3).url,
      chapterTitle: chapter(a, 3).title,
      chapterIndex: 3,
      chapterCount: 8,
    );
    final adding = pin(a, 3);
    final other = pin(b, 1);
    await Future.wait([adding, other]);
    await state.removeChapterBookmark(state.bookmarksFor(a).single.key);
    expect(state.bookmarksFor(a), isEmpty);
    expect(state.progressFor(a.bookUrl)?.chapterIndex, 3);

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.bookmarksFor(a), isEmpty);
    expect(restored.bookmarksFor(b).single.chapterIndex, 1);
    expect(restored.progressFor(a.bookUrl)?.chapterIndex, 3);
  });

  test('indexIn 优先匹配章节链接，找不到时回退序号', () {
    final a = book('目录漫画');
    final bookmark = ChapterBookmark(
      book: a,
      chapter: Chapter(title: '旧标题', url: '/c2'),
      chapterIndex: 0,
      at: 1,
    );
    final chapters = [
      Chapter(title: '第一话', url: '/c1'),
      Chapter(title: '第二话', url: '/c2'),
    ];
    expect(bookmark.indexIn(chapters), 1);
    expect(
      ChapterBookmark(
        book: a,
        chapter: Chapter(title: '已失效', url: '/gone'),
        chapterIndex: 0,
        at: 1,
      ).indexIn(chapters),
      0,
    );
    expect(bookmark.indexIn(const []), isNull);
  });
}
