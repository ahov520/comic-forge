import 'package:comic_forge/state/app_state.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('incognito suppresses automatic history and position writes', () async {
    final state = AppState();
    addTearDown(state.dispose);
    final book = Book.fromJson({
      'name': '示例',
      'bookUrl': 'https://comic.example/book/1',
      'sourceId': 'source-1',
    });

    await state.setIncognitoMode(true);
    await state.recordSearch('私密关键词');
    await state.saveProgress(
      book,
      chapterUrl: 'https://comic.example/chapter/1',
      chapterTitle: '第一话',
      chapterIndex: 0,
      chapterCount: 5,
    );
    await state.saveScrollOffset('https://comic.example/chapter/1', 128.0);
    await state.saveReaderPage('https://comic.example/chapter/1', 3);

    expect(state.searchHistory, isEmpty);
    expect(state.progress, isEmpty);
    expect(state.readingHistory, isEmpty);
    expect(state.scrollOffsets, isEmpty);
    expect(state.readerPages, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cf.incognitoMode'), isTrue);
    expect(prefs.containsKey('cf.progress'), isFalse);
    expect(prefs.containsKey('cf.readingHistory'), isFalse);

    // Normal mode is restored immediately without discarding old records.
    await state.setIncognitoMode(false);
    await state.recordSearch('公开关键词');
    await state.saveProgress(
      book,
      chapterUrl: 'https://comic.example/chapter/1',
      chapterTitle: '第一话',
      chapterIndex: 0,
      chapterCount: 5,
    );
    expect(state.searchHistory, ['公开关键词']);
    expect(state.progress.length, 1);
    expect(state.readingHistory.length, 1);
  });

  test('incognito switch survives app state reload', () async {
    final old = AppState();
    await old.setIncognitoMode(true);
    old.dispose();

    final next = AppState();
    addTearDown(next.dispose);
    await next.load();
    expect(next.incognitoMode, isTrue);
  });
}
