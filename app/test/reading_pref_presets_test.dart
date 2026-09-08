import 'dart:convert';

import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/reading_pref_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });
  tearDown(() => state.dispose());

  Future<AppState> restart() async {
    final restored = AppState();
    addTearDown(restored.dispose);
    await restored.load();
    return restored;
  }

  test('保存当前阅读偏好，应用后即时覆盖并跨重启保留', () async {
    await state.setReaderMode('paged');
    await state.setReaderBrightness(0.4);
    await state.setReaderVolumeKeys(true);
    final id = await state.saveCurrentReaderPreset('  夜间翻页  ');
    expect(state.readerPresets.presets.single.name, '夜间翻页');
    expect(state.activeReaderPreset?.id, id);

    await state.setReaderMode('scroll');
    await state.setReaderBrightness(1);
    await state.setReaderVolumeKeys(false);
    expect(state.activeReaderPreset, isNull);

    expect(await state.applyReaderPreset(id), isTrue);
    expect(state.readerMode, 'paged');
    expect(state.readerBrightness, 0.4);
    expect(state.readerVolumeKeys, isTrue);
    expect(state.activeReaderPreset?.name, '夜间翻页');

    final restored = await restart();
    expect(restored.readerPresets.presets.single.name, '夜间翻页');
    expect(restored.readerMode, 'paged');
    expect(restored.readerBrightness, 0.4);
    expect(restored.readerVolumeKeys, isTrue);
    expect(restored.activeReaderPreset?.id, id);
  });

  test('空名、重复名、超长名和数量上限被拒绝，重命名自己合法', () async {
    final id = await state.saveCurrentReaderPreset('Bedtime');
    for (final name in ['', ' \n ', 'bedtime', ' Bedtime ', '字' * 31]) {
      await expectLater(
        state.saveCurrentReaderPreset(name),
        throwsArgumentError,
      );
    }
    await state.readerPresets.rename(id, ' Bedtime ');
    final other = await state.saveCurrentReaderPreset('滚动');
    await expectLater(
      state.readerPresets.rename(other, 'bedtime'),
      throwsArgumentError,
    );
    expect(state.readerPresets.presets.map((p) => p.name), ['Bedtime', '滚动']);

    for (var i = 2; i < ReadingPrefPresets.maxCount; i++) {
      await state.saveCurrentReaderPreset('预设$i');
    }
    await expectLater(state.saveCurrentReaderPreset('超出'), throwsArgumentError);
  });

  test('重命名、更新和删除不影响当前阅读偏好，删除后跨重启消失', () async {
    await state.setReaderMode('paged');
    final id = await state.saveCurrentReaderPreset('翻页');
    await state.readerPresets.rename(id, '平板翻页');
    await state.setReaderMode('scroll');
    await state.updateReaderPreset(id);
    expect(state.readerPresets.byId(id)!.mode, 'scroll');
    expect(state.readerMode, 'scroll');
    await state.readerPresets.delete(id);
    expect(state.readerMode, 'scroll');
    expect(state.readerPresets.presets, isEmpty);
    expect(state.activeReaderPreset, isNull);
    expect((await restart()).readerPresets.presets, isEmpty);
  });

  test('连续写入串行持久化，应用未知 id 为 false', () async {
    await Future.wait([
      state.saveCurrentReaderPreset('A'),
      state.saveCurrentReaderPreset('B'),
      state.setReaderBrightness(0.5),
    ]);
    expect(await state.applyReaderPreset('missing'), isFalse);
    final restored = await restart();
    expect(restored.readerPresets.presets.map((p) => p.name), ['A', 'B']);
  });

  test('恢复过滤坏条目、重复名称和无效 activeId', () async {
    await (await SharedPreferences.getInstance()).setString(
      ReadingPrefPresets.prefsKey,
      jsonEncode({
        'presets': [
          {
            'id': 'one',
            'name': '  保留  ',
            'brightness': 0.5,
            'mode': 'paged',
            'volumeKeys': true,
            'at': 1,
          },
          {
            'id': 'one',
            'name': '重复 ID',
            'brightness': 1,
            'mode': 'scroll',
            'volumeKeys': false,
            'at': 2,
          },
          {
            'id': 'two',
            'name': '保留',
            'brightness': 0.8,
            'mode': 'scroll',
            'volumeKeys': false,
            'at': 3,
          },
          {
            'id': '',
            'name': '坏 ID',
            'brightness': 1,
            'mode': 'scroll',
            'at': 4,
          },
          {
            'id': 'three',
            'name': 42,
            'brightness': 1,
            'mode': 'scroll',
            'at': 5,
          },
          null,
          {
            'id': 'four',
            'name': '另一个',
            'brightness': 2,
            'mode': 'ltr',
            'volumeKeys': true,
            'at': 6,
          },
        ],
        'activeId': 'missing',
      }),
    );
    final restored = await restart();
    expect(restored.readerPresets.presets.map((p) => p.id), ['one', 'four']);
    expect(restored.readerPresets.presets.first.name, '保留');
    expect(restored.readerPresets.presets.first.brightness, 0.5);
    expect(restored.readerPresets.presets.last.brightness, 1.0);
    expect(restored.readerPresets.presets.last.mode, 'scroll');
    expect(restored.readerPresets.lastAppliedId, isNull);
  });

  for (final saved in [null, 42, '{broken', '[]']) {
    test('缺失或损坏预设不影响当前阅读偏好：$saved', () async {
      await state.setReaderMode('paged');
      await state.setReaderBrightness(0.3);
      final prefs = await SharedPreferences.getInstance();
      if (saved is String) {
        await prefs.setString(ReadingPrefPresets.prefsKey, saved);
      }
      if (saved is int) await prefs.setInt(ReadingPrefPresets.prefsKey, saved);
      final restored = await restart();
      expect(restored.readerMode, 'paged');
      expect(restored.readerBrightness, 0.3);
      expect(restored.readerPresets.presets, isEmpty);
    });
  }
}
