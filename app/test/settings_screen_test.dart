import 'dart:io';

import 'package:comic_forge/backup_service.dart';
import 'package:comic_forge/services/download_store.dart';
import 'package:comic_forge/services/image_cache_store.dart';
import 'package:comic_forge/services/source_service.dart';
import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/state/download_queue.dart';
import 'package:comic_forge/state/shelf_update_notifications.dart';
import 'package:comic_forge/state/source_update.dart';
import 'package:comic_forge/state/shelf_update_schedule.dart';
import 'package:comic_forge/ui/downloads_screen.dart';
import 'package:comic_forge/ui/settings_screen.dart';
import 'package:comic_forge/ui/source_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_test_image.dart';
import 'support/fake_shelf_update_notifier.dart';

Future<void> _showSettings(
  WidgetTester tester,
  AppState state, {
  Brightness brightness = Brightness.light,
  Size size = const Size(320, 640),
  double textScale = 2,
  Future<bool> Function(String fileName, String text)? saveLocalBackup,
  Future<void> Function(String fileName, String text)? shareLocalBackup,
  Future<String?> Function()? pickLocalBackup,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SettingsScreen(
          state: state,
          saveLocalBackup: saveLocalBackup,
          shareLocalBackup: shareLocalBackup,
          pickLocalBackup: pickLocalBackup,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
  });
  tearDown(() {
    state.dispose();
    SourceService.instance.adBlock = null;
    SourceService.instance.debugResetNetworkPolicy();
  });

  testWidgets('源订阅入口显示状态并打开源管理', (tester) async {
    await _showSettings(
      tester,
      state,
      size: const Size(340, 1200),
      textScale: 1,
    );
    expect(find.text('源订阅'), findsOneWidget);
    expect(find.text('订阅远程源列表并检查更新'), findsOneWidget);
    const repo = 'https://cdn.example.com/store.json';
    await state.addRepoSubscribed(repo, const []);
    state.repoLastRefresh[repo] = DateTime(
      2026,
      9,
      8,
      11,
      20,
    ).millisecondsSinceEpoch;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('1 个订阅 · 上次成功 09-08 11:20'), findsOneWidget);
    state.repoUpdates[repo] = RepoUpdateState(
      lastError: 'HTTP 404 for $repo',
      lastFailedAt: DateTime(2026, 9, 8, 12).millisecondsSinceEpoch,
    );
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('1 个订阅 · 1 个上次失败'), findsOneWidget);
    await tester.tap(find.text('源订阅'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
    expect(find.text('已订阅仓库'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置行保留 14px 标题，操作图标与箭头对齐且整块区域可点击', (tester) async {
    await _showSettings(
      tester,
      state,
      size: const Size(340, 1200),
      textScale: 1,
    );
    final firstTitle = tester.getRect(find.text('深色模式'));
    for (final label in [
      '深色模式',
      '阅读预设',
      '源订阅',
      'WebDAV 备份 / 恢复',
      '广告拦截规则',
      '域名黑名单',
      'Comic Forge v0.1.0',
    ]) {
      final title = find.text(label);
      final tile = find.widgetWithText(ListTile, label);
      final leading = find
          .descendant(of: tile, matching: find.byType(Icon))
          .first;
      expect(tester.getRect(title).left, firstTitle.left);
      expect(tester.getRect(leading).left, 24);
      expect(
        tester.getRect(leading).center.dy,
        closeTo(tester.getRect(tile).center.dy, 0.5),
      );
      expect(
        tester.renderObject<RenderParagraph>(title).text.style?.fontSize,
        14,
      );
    }
    final arrow = tester.getRect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'WebDAV 备份 / 恢复'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    final toggle = tester.getRect(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, '深色模式'),
        matching: find.byType(Switch),
      ),
    );
    expect(toggle.right, arrow.right);
    expect(toggle.width, greaterThanOrEqualTo(48));
    expect(toggle.height, greaterThanOrEqualTo(48));
    final wasDark = state.darkMode;
    await tester.tapAt(Offset(toggle.center.dx, toggle.top + 2));
    await tester.pumpAndSettle();
    expect(state.darkMode, !wasDark);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(state.darkMode, wasDark);
    expect(
      tester.getRect(find.byIcon(Icons.upload_file_outlined)).right,
      arrow.right,
    );
    await state.setAdBlock('{"urlRules":["tracking"]}');
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byIcon(Icons.delete_outline)).right,
      arrow.right,
    );
    final clear = tester.getRect(find.byTooltip('清除规则'));
    expect(clear.width, greaterThanOrEqualTo(48));
    expect(clear.height, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(clear.left + 2, clear.center.dy));
    await tester.pumpAndSettle();
    expect(state.adBlock, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('设置状态随外部更新刷新，窄屏大字号仍可清除规则：${brightness.name}', (tester) async {
      await _showSettings(tester, state, brightness: brightness);
      await tester.scrollUntilVisible(find.text('WebDAV 备份 / 恢复'), 200);
      await tester.pumpAndSettle();
      expect(find.text('未配置服务器'), findsOneWidget);
      await state.setWebDavConfig({
        'url': 'https://backup.example/dav/comic-forge',
      });
      await state.setAdBlock('{"urlRules":["tracking","advert"]}');
      await tester.pumpAndSettle();
      expect(find.text('backup.example'), findsOneWidget);
      expect(find.text('已启用 · 2 条图片规则'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('清除规则'));
      await tester.tap(find.byTooltip('清除规则'));
      await tester.pumpAndSettle();
      expect(state.adBlock, isNull);
      expect(find.byTooltip('导入广告规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('WebDAV 大字号面板在键盘展开后仍可滚动到备份与恢复按钮', (tester) async {
    await _showSettings(tester, state);
    await tester.scrollUntilVisible(find.text('WebDAV 备份 / 恢复'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV 备份 / 恢复'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('备份'));
    expect(find.text('备份').hitTestable(), findsOneWidget);
    expect(find.text('恢复').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('备份')).bottom, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('书架自动检查开关和间隔可设置，窄屏大字号可选择全部预设', (tester) async {
    await _showSettings(tester, state);
    final toggle = find.widgetWithText(SwitchListTile, '自动检查书架更新');
    final interval = find.widgetWithText(ListTile, '检查间隔');
    await tester.scrollUntilVisible(interval, 160);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(interval).enabled, isFalse);
    await tester.scrollUntilVisible(toggle, -160);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.shelfUpdateSchedule.enabled, isTrue);
    await tester.ensureVisible(interval);
    await tester.pumpAndSettle();
    await tester.tap(interval);
    await tester.pumpAndSettle();
    expect(find.text('每 1 小时'), findsOneWidget);
    expect(find.text('每 24 小时'), findsOneWidget);
    await tester.ensureVisible(find.text('每 24 小时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每 24 小时'));
    await tester.pumpAndSettle();
    expect(state.shelfUpdateSchedule.interval, ShelfUpdateInterval.daily);
    expect(find.text('每 24 小时'), findsOneWidget);

    final restored = ShelfUpdateSchedule();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.interval, ShelfUpdateInterval.daily);
    await tester.scrollUntilVisible(toggle, -160);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.shelfUpdateSchedule.enabled, isFalse);
    await restored.load();
    expect(restored.enabled, isFalse);
    expect(restored.interval, ShelfUpdateInterval.daily);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('更新通知开关默认关闭，授权后可开启并跨重启保留', (tester) async {
    await _showSettings(
      tester,
      state,
      size: const Size(340, 1200),
      textScale: 1,
    );
    final toggle = find.widgetWithText(SwitchListTile, '更新通知');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await state.setUpdateNotificationsEnabled(true), isTrue);
    await tester.pump();
    expect(state.updateNotifications.enabled, isTrue);

    final restored = ShelfUpdateNotifications();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(await state.setUpdateNotificationsEnabled(false), isTrue);
    await tester.pump();
    expect(state.updateNotifications.enabled, isFalse);
    await restored.load();
    expect(restored.enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未授予通知权限时开关保持关闭并提示', (tester) async {
    final notifier = FakeShelfUpdateNotifier(permissionGranted: false);
    final denied = AppState(updateNotifier: notifier);
    addTearDown(denied.dispose);
    await _showSettings(
      tester,
      denied,
      size: const Size(340, 1200),
      textScale: 1,
    );
    final toggle = find.widgetWithText(SwitchListTile, '更新通知');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.pump();
    await tester.pump();
    expect(denied.updateNotifications.enabled, isFalse);
    expect(find.text('未授予通知权限，可在系统设置中开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    '非 Android 不显示本地备份入口',
    (tester) async {
      await _showSettings(tester, state);
      expect(find.text('导出本地备份'), findsNothing);
      expect(find.text('导入本地备份'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'Android 显示本地备份入口',
    (tester) async {
      await _showSettings(
        tester,
        state,
        size: const Size(340, 1400),
        textScale: 1,
      );
      await tester.scrollUntilVisible(find.text('导出本地备份'), 200);
      expect(find.text('导出本地备份'), findsOneWidget);
      expect(find.text('导入本地备份'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Android 导出可分享或保存，导入可选择合并或覆盖',
    (tester) async {
      String? sharedName;
      String? savedName;
      var imported = false;
      state.sources.add(
        ComicSource.fromPpcatFlat({
          'bookSourceName': '源A',
          'bookSourceUrl': 'https://m.example.com/a',
          'ruleSearchUrl': '/s',
        }),
      );
      final backup = BackupService.exportJson(state);
      await _showSettings(
        tester,
        state,
        size: const Size(340, 1400),
        textScale: 1,
        shareLocalBackup: (name, text) async {
          sharedName = name;
          expect(text, contains('"app":"comic-forge"'));
        },
        saveLocalBackup: (name, text) async {
          savedName = name;
          expect(text, contains('"bookmarks"'));
          return true;
        },
        pickLocalBackup: () async => backup,
      );
      await tester.scrollUntilVisible(find.text('导出本地备份'), 200);
      await tester.tap(find.text('导出本地备份'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsOneWidget);
      expect(find.text('保存到文件'), findsOneWidget);
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      expect(sharedName, startsWith('comic-forge-backup-'));
      expect(find.textContaining('已分享备份'), findsWidgets);

      await tester.tap(find.text('导出本地备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到文件'));
      await tester.pumpAndSettle();
      expect(savedName, startsWith('comic-forge-backup-'));

      await tester.scrollUntilVisible(find.text('导入本地备份'), 80);
      await tester.tap(find.text('导入本地备份'));
      await tester.pumpAndSettle();
      expect(find.text('合并导入'), findsOneWidget);
      expect(find.text('覆盖导入'), findsOneWidget);
      await tester.tap(find.text('合并导入'));
      await tester.pumpAndSettle();
      imported = true;
      expect(imported, isTrue);
      expect(find.textContaining('合并完成'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'Android 下载管理行显示占用并进入清理页',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-settings-dl-'),
      );
      final cacheDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('comic-forge-settings-cache-'),
      );
      addTearDown(() async {
        await directory!.delete(recursive: true);
        await cacheDir!.delete(recursive: true);
      });
      final queue = DownloadQueue(
        sourceFor: (_) => null,
        store: DownloadStore(directory: () async => directory!),
        loadImages: (_, _) async => (
          urls: ['https://download.example/page.png'],
          headers: <String, String>{},
        ),
        fetchBytes: (_, _) async => downloadTestImage(),
      );
      final book = Book(
        sourceId: 'settings-dl',
        name: '漫画',
        bookUrl: 'https://download.example/book',
      );
      final chapter = Chapter(title: '第1话', url: 'https://download.example/c1');
      state.dispose();
      state = AppState(
        downloadQueue: queue,
        imageCache: ImageCacheStore(
          manager: _SettingsCacheManager(),
          directory: () async => cacheDir!,
        ),
      );
      await tester.runAsync(() async {
        await File(
          '${cacheDir!.path}/cached.bin',
        ).writeAsBytes(List.filled(64, 1));
        await queue.enqueue(book, [chapter], [0]);
        await queue.idle;
      });
      await tester.runAsync(() async {
        await _showSettings(
          tester,
          state,
          size: const Size(340, 1400),
          textScale: 1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('下载管理'), 200);
      await tester.pumpAndSettle();
      expect(find.textContaining('离线约'), findsOneWidget);
      expect(find.textContaining('图片缓存约 64 B'), findsOneWidget);
      await tester.tap(find.text('下载管理'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(find.byTooltip('清理存储'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}

class _SettingsCacheManager extends Fake implements BaseCacheManager {
  @override
  Future<void> emptyCache() async {}

  @override
  Future<void> removeFile(String key) async {}
}
