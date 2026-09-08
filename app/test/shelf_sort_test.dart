import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/shelf_sort.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 8, 12);

  Book book({
    required String name,
    String author = '',
    String kind = '连载中',
    String url = '',
    String updateTime = '',
  }) => Book(
    name: name,
    author: author,
    kind: kind,
    bookUrl: url.isEmpty ? '/$name' : url,
    updateTime: updateTime,
  );

  List<String> names(Iterable<Book> books) =>
      books.map((item) => item.name).toList();

  test('解析源站更新时间，无法识别时回退 0', () {
    expect(parseComicUpdateTime(''), 0);
    expect(parseComicUpdateTime('连载中'), 0);
    expect(parseComicUpdateTime('1694160000'), 1694160000 * 1000);
    expect(parseComicUpdateTime('1694160000000'), 1694160000000);
    expect(
      parseComicUpdateTime('2024-01-15', now: now),
      DateTime(2024, 1, 15).millisecondsSinceEpoch,
    );
    expect(
      parseComicUpdateTime('2024年3月5日 8:09', now: now),
      DateTime(2024, 3, 5, 8, 9).millisecondsSinceEpoch,
    );
    expect(
      parseComicUpdateTime('昨天', now: now),
      DateTime(2026, 9, 7).millisecondsSinceEpoch,
    );
    expect(
      parseComicUpdateTime('3小时前', now: now),
      now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
    );
    expect(
      parseComicUpdateTime('12-20', now: now),
      DateTime(2025, 12, 20).millisecondsSinceEpoch,
    );
  });

  test('损坏或未知排序键回退最近阅读', () {
    expect(ShelfSort.parse(null), ShelfSort.recentlyRead);
    expect(ShelfSort.parse(42), ShelfSort.recentlyRead);
    expect(ShelfSort.parse('nope'), ShelfSort.recentlyRead);
    expect(ShelfSort.parse(''), ShelfSort.recentlyRead);
    expect(ShelfSort.parse(' title '), ShelfSort.title);
    expect(ShelfSort.parse('author'), ShelfSort.author);
  });

  test('先分组、搜索和连载状态，再按选定规则排序', () {
    final moon = book(name: 'Moon 漫画', author: '青山', url: '/moon');
    final extra = book(
      name: 'Moon 番外',
      author: 'Alice',
      kind: '已完结',
      url: '/extra',
      updateTime: '2024-02-01',
    );
    final mountain = book(
      name: '山海卷',
      author: 'Alice',
      kind: '已完结',
      url: '/mountain',
      updateTime: '2024-03-01',
    );
    final grouped = {moon.bookUrl, extra.bookUrl};
    final visible = visibleShelfBooks(
      [mountain, extra, moon],
      matchesGroup: (item) => grouped.contains(item.bookUrl),
      query: '  mOoN  ',
      kindFilter: 2,
      sort: ShelfSort.title,
      readAt: (item) => item.bookUrl == extra.bookUrl ? 9 : 1,
    );
    expect(names(visible), [extra.name]);
  });

  test('最近阅读、更新时间、书名和作者的排序与并列规则', () {
    final unread = book(name: '未读', url: '/unread');
    final older = book(
      name: '旧作',
      author: 'Zed',
      url: '/old',
      updateTime: '昨天',
    );
    final newer = book(
      name: '新作',
      author: '',
      url: '/new',
      updateTime: '今天',
    );
    final named = book(name: 'Beta', author: 'Alice', url: '/beta');
    final books = [newer, unread, named, older];
    final readAt = {older.bookUrl: 10, named.bookUrl: 20};
    final catalogAt = {unread.bookUrl: DateTime(2026, 8, 1).millisecondsSinceEpoch};

    expect(
      names(
        visibleShelfBooks(
          books,
          matchesGroup: (_) => true,
          sort: ShelfSort.recentlyRead,
          readAt: (item) => readAt[item.bookUrl] ?? 0,
        ),
      ),
      [named.name, older.name, newer.name, unread.name],
    );
    expect(
      names(
        visibleShelfBooks(
          books,
          matchesGroup: (_) => true,
          sort: ShelfSort.updateTime,
          catalogAt: (item) => catalogAt[item.bookUrl] ?? 0,
          now: now,
        ),
      ),
      [newer.name, older.name, unread.name, named.name],
    );
    expect(
      names(
        visibleShelfBooks(
          books,
          matchesGroup: (_) => true,
          sort: ShelfSort.title,
        ),
      ),
      [named.name, newer.name, older.name, unread.name],
    );
    expect(
      names(
        visibleShelfBooks(
          books,
          matchesGroup: (_) => true,
          sort: ShelfSort.author,
        ),
      ),
      [named.name, older.name, newer.name, unread.name],
    );
  });

  test('排序偏好跨重启保留，缺失或损坏回退最近阅读', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    final late = book(name: 'Zed', url: '/zed');
    final early = book(name: 'Amy', url: '/amy');
    await state.toggleShelf(late);
    await state.toggleShelf(early);
    state.progress[late.bookUrl] = ReadingProgress(
      bookUrl: late.bookUrl,
      sourceId: '',
      chapterUrl: '/c',
      chapterTitle: '',
      chapterIndex: 0,
      chapterCount: 1,
      at: 9,
    );
    state.progress[early.bookUrl] = ReadingProgress(
      bookUrl: early.bookUrl,
      sourceId: '',
      chapterUrl: '/c',
      chapterTitle: '',
      chapterIndex: 0,
      chapterCount: 1,
      at: 1,
    );
    expect(state.shelfBooks().map((item) => item.name), [late.name, early.name]);
    await state.setShelfSort(ShelfSort.title);
    expect(state.shelfBooks().map((item) => item.name), [early.name, late.name]);

    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.shelfSort, ShelfSort.title);
    expect(restored.shelfBooks().map((item) => item.name), [
      early.name,
      late.name,
    ]);

    for (final saved in [null, 42, '{bad', 'nope']) {
      SharedPreferences.setMockInitialValues({
        'cf.shelfSort': ?saved,
      });
      final fallback = AppState();
      addTearDown(fallback.dispose);
      await fallback.load();
      expect(fallback.shelfSort, ShelfSort.recentlyRead);
    }
  });
}
